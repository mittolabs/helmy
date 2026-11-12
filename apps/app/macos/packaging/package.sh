#!/usr/bin/env bash
# Packages the universal build as one .dmg for Apple silicon and one for Intel, each
# with Helmy beside an Applications shortcut to drag it onto: package.sh <tag>
# Run from apps/app after `flutter build macos --release`.
set -euo pipefail
tag=$1
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
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname "Helmy" -srcfolder "$stage" -ov -format UDZO "Helmy-$tag-macos-$name.dmg"
  rm -rf "$stage"
done
ls -la Helmy-"$tag"-macos-*.dmg
