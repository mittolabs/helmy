#!/usr/bin/env bash
# Packages the universal build as one .dmg for Apple silicon and one for Intel, each
# with Helmy beside an Applications shortcut to drag it onto: package.sh <tag>
# Run from apps/app after `flutter build macos --release`.
set -euo pipefail
tag=$1
here=$(cd "$(dirname "$0")" && pwd)
universal=build/macos/Build/Products/Release/Helmy.app
for arch in arm64 x86_64; do
  name=$([ "$arch" = arm64 ] && echo arm64 || echo x64)
  stage=$(mktemp -d)
  cp -R "$universal" "$stage/Helmy.app"
  # Every universal binary in the app keeps only this architecture: half the download.
  while IFS= read -r -d '' f; do
    if lipo -info "$f" 2>/dev/null | grep -q "Architectures in the fat file"; then
      lipo "$f" -thin "$arch" -output "$f.thin" && mv "$f.thin" "$f"
    fi
  done < <(find "$stage/Helmy.app" -type f -print0)
  # Thinning breaks the signature: signed again, ad hoc, as the build was.
  codesign --force --deep --sign - "$stage/Helmy.app"
  codesign --verify --deep --strict "$stage/Helmy.app"
  [ "$(lipo -archs "$stage/Helmy.app/Contents/MacOS/Helmy")" = "$arch" ]
  out="Helmy-$tag-macos-$name.dmg"
  # The window people see: Helmy beside Applications, big, on a background with an arrow
  # between them (background.tiff, drawn for 1x and 2x). create-dmg lays it out through
  # Finder; where that fails, the same two icons in a plain window.
  if command -v create-dmg >/dev/null && create-dmg --volname Helmy --background "$here/background.tiff" \
      --window-pos 200 120 --window-size 640 400 --icon-size 128 --text-size 13 \
      --icon Helmy.app 170 200 --hide-extension Helmy.app --app-drop-link 470 200 \
      "$out" "$stage"; then
    :
  else
    echo "::warning::create-dmg did not lay out the window; a plain one instead"
    rm -f "$out"
    ln -s /Applications "$stage/Applications"
    hdiutil create -volname "Helmy" -srcfolder "$stage" -ov -format UDZO "$out"
  fi
  rm -rf "$stage"
done
ls -la Helmy-"$tag"-macos-*.dmg
