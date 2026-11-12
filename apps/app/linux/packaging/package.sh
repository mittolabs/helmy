#!/usr/bin/env bash
# Packages the Linux build as a .deb and an AppImage: package.sh <tag> <x64|arm64>
# Run from apps/app after `flutter build linux --release`.
set -euo pipefail
tag=$1 arch=$2
version=${tag#v}
bundle=build/linux/$arch/release/bundle
here=linux/packaging
deb_arch=$([ "$arch" = x64 ] && echo amd64 || echo arm64)
img_arch=$([ "$arch" = x64 ] && echo x86_64 || echo aarch64)
work=$(mktemp -d)

# .deb: the bundle in /opt/helmy, in the app menu with its icon. Not on the PATH:
# `helmy` there is `helmy run`, which Helmy sets up itself.
pkg=$work/deb
mkdir -p "$pkg/DEBIAN" "$pkg/opt/helmy" "$pkg/usr/share/applications" "$pkg/usr/share/icons/hicolor/256x256/apps"
cp -R "$bundle"/. "$pkg/opt/helmy/"
sed 's#^Exec=helmy#Exec=/opt/helmy/helmy#' "$here/helmy.desktop" > "$pkg/usr/share/applications/helmy.desktop"
cp "$here/helmy.png" "$pkg/usr/share/icons/hicolor/256x256/apps/helmy.png"
cat > "$pkg/DEBIAN/control" <<CONTROL
Package: helmy
Version: $version
Architecture: $deb_arch
Maintainer: Mittolabs
Homepage: https://helmy.ke
Depends: libgtk-3-0, libstdc++6
Section: utils
Priority: optional
Description: Helmy, one assistant for every AI you pay for
 Tell Helmy what you want done. It works through your Claude and ChatGPT
 subscriptions, plus a free connection, and picks one for each message.
CONTROL
[ "$version" = dev ] && sed -i 's/^Version: .*/Version: 0.0.0-dev/' "$pkg/DEBIAN/control"
dpkg-deb --root-owner-group --build "$pkg" "Helmy-$tag-linux-$arch.deb"

# AppImage: one file that runs on most distributions.
app=$work/Helmy.AppDir
mkdir -p "$app"
cp -R "$bundle"/. "$app/"
cp "$here/helmy.desktop" "$app/helmy.desktop"
cp "$here/helmy.png" "$app/helmy.png"
cat > "$app/AppRun" <<'RUN'
#!/bin/sh
here=$(dirname "$(readlink -f "$0")")
exec "$here/helmy" "$@"
RUN
chmod +x "$app/AppRun"
tool=$work/appimagetool
curl -fsSL -o "$tool" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$img_arch.AppImage"
chmod +x "$tool"
ARCH=$img_arch APPIMAGE_EXTRACT_AND_RUN=1 "$tool" --no-appstream "$app" "Helmy-$tag-linux-$arch.AppImage"
ls -la Helmy-"$tag"-linux-"$arch".*
