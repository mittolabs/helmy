#!/bin/sh
# Installs Helmy on macOS or Linux, from its latest release on GitHub:
#   curl -fsSL https://helmy.ke/install.sh | sh
# macOS: the .dmg for this Mac's chip, into /Applications (or ~/Applications).
# Linux: the AppImage for this machine, into ~/.local/share/helmy, in the app menu.
set -eu

repo=https://github.com/mittolabs/helmy
say() { printf '%s\n' "$*"; }
fail() { say "helmy: $*" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || fail "curl is needed to download Helmy."

# The latest release's tag, from where GitHub's "latest" link leads.
tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$repo/releases/latest" | sed 's#.*/tag/##')
case $tag in v*) ;; *) fail "couldn't find the latest release. See $repo/releases" ;; esac

arch=$(uname -m)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

case $(uname -s) in
Darwin)
  case $arch in arm64) build=arm64 ;; x86_64) build=x64 ;; *) fail "no macOS build for $arch." ;; esac
  # Under Rosetta, a terminal says x86_64 on Apple silicon: the chip decides.
  [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = 1 ] && build=arm64
  file="Helmy-$tag-macos-$build.dmg"
  say "Downloading Helmy $tag for $([ "$build" = arm64 ] && echo 'Apple silicon' || echo Intel)..."
  curl -fSL --progress-bar -o "$tmp/$file" "$repo/releases/download/$tag/$file"
  hdiutil attach -nobrowse -readonly -quiet -mountpoint "$tmp/mnt" "$tmp/$file"
  dest=/Applications
  [ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
  osascript -e 'tell application "Helmy" to quit' >/dev/null 2>&1 || true
  rm -rf "$dest/Helmy.app"
  cp -R "$tmp/mnt/Helmy.app" "$dest/"
  hdiutil detach -quiet "$tmp/mnt"
  say "Helmy $tag is in $dest. Opening it..."
  open "$dest/Helmy.app"
  ;;
Linux)
  case $arch in x86_64 | amd64) build=x64 ;; aarch64 | arm64) build=arm64 ;; *) fail "no Linux build for $arch." ;; esac
  file="Helmy-$tag-linux-$build.AppImage"
  home="${XDG_DATA_HOME:-$HOME/.local/share}"
  dir="$home/helmy"
  mkdir -p "$dir" "$home/applications" "$home/icons/hicolor/256x256/apps"
  say "Downloading Helmy $tag for $arch..."
  curl -fSL --progress-bar -o "$tmp/$file" "$repo/releases/download/$tag/$file"
  chmod +x "$tmp/$file"
  mv "$tmp/$file" "$dir/Helmy.AppImage"
  # The icon, from inside the AppImage, and an entry in the app menu.
  (cd "$tmp" && "$dir/Helmy.AppImage" --appimage-extract helmy.png >/dev/null 2>&1 \
    && cp squashfs-root/helmy.png "$home/icons/hicolor/256x256/apps/helmy.png") || true
  cat > "$home/applications/helmy.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Helmy
Comment=Dream it, do it: tell Helmy what you want done
Exec="$dir/Helmy.AppImage" %U
Icon=helmy
Terminal=false
Categories=Utility;Development;
StartupWMClass=com.mittolabs.helmy
EOF
  say "Helmy $tag is installed: open it from your app menu, or run $dir/Helmy.AppImage"
  say "(The AppImage needs FUSE; on Ubuntu 24.04 and later: sudo apt install libfuse2t64)"
  ;;
*)
  fail "this installer is for macOS and Linux. On Windows, in PowerShell: irm https://helmy.ke/install.ps1 | iex"
  ;;
esac
