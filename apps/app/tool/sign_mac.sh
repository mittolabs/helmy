#!/bin/sh
# Signs the macOS debug app with a developer's own certificate, when they
# name one in .signing.local at the repository root: the certificate's SHA-1,
# from `security find-identity -v -p codesigning`. Kept out of git.
#
# Why: ad hoc, every build is a new app to macOS, which then forgets the
# permissions Helmy was given (Screen Recording, Accessibility). Signed by one
# certificate, it stays the same app across rebuilds.
#
#   tool/sign_mac.sh build/macos/Build/Products/Debug/Helmy.app
set -e
app=$1
root=$(git rev-parse --show-toplevel)
file="$root/.signing.local"
[ -f "$file" ] || exit 0
id=$(tr -d '[:space:]' < "$file")
entitlements="$root/apps/app/macos/Runner/DebugProfile.entitlements"
# What is inside first, then the app itself.
for code in "$app"/Contents/Frameworks/*.framework "$app"/Contents/Frameworks/*.dylib "$app"/Contents/MacOS/*.dylib; do
  [ -e "$code" ] && codesign --force --sign "$id" "$code"
done
codesign --force --sign "$id" --entitlements "$entitlements" "$app"
codesign --verify --deep --strict "$app"
echo "Signed with $(codesign -dvv "$app" 2>&1 | grep '^Authority=' | head -1 | cut -d= -f2)"
