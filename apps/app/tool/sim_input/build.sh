#!/bin/sh
# Builds Helmy's simulator input helper into assets/helmy/bin/sim_input.
#
# It links AXe's simulator frameworks (installed by Homebrew, MIT) and needs
# the private headers from Meta's idb (MIT) only to compile: fetched here into
# a temporary folder, never kept. Run it after changing sim_input.swift, or
# when a new AXe changes its frameworks. Needs AXe installed (brew install
# cameroncooke/axe/axe) and Xcode.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
app=$(cd "$here/../.." && pwd)
out="$app/assets/helmy/bin/sim_input"

axe=$(command -v axe || true)
[ -n "$axe" ] || { echo "AXe is not installed: brew install cameroncooke/axe/axe" >&2; exit 1; }
frameworks="$(cd "$(dirname "$(realpath "$axe")")/../libexec/Frameworks" && pwd)"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "Fetching idb's private headers"
git clone -q --depth 1 --filter=blob:none --sparse https://github.com/facebook/idb.git "$work/idb"
git -C "$work/idb" sparse-checkout set PrivateHeaders
headers="$work/idb/PrivateHeaders"

includes="-Xcc -I$headers"
for d in AccessibilityPlatformTranslation AXRuntime CoreSimDeviceIO CoreSimulator \
  CoreSimulatorUtilities SimulatorKit; do
  includes="$includes -Xcc -I$headers/$d"
done

for arch in arm64 x86_64; do
  echo "Building for $arch"
  # shellcheck disable=SC2086
  xcrun swiftc -O -target "$arch-apple-macos13" -F "$frameworks" $includes \
    -framework FBControlCore -framework FBSimulatorControl \
    "$here/sim_input.swift" -o "$work/sim_input-$arch"
done
lipo -create "$work/sim_input-arm64" "$work/sim_input-x86_64" -output "$work/sim_input"

# Found wherever Homebrew keeps AXe (Apple silicon or Intel), whatever its
# version, rather than at this Mac's path.
for fw in FBControlCore FBSimulatorControl; do
  old=$(otool -L "$work/sim_input" | awk -v f="$fw" '$1 ~ "/"f"$" {print $1; exit}')
  install_name_tool -change "$old" "@rpath/$fw.framework/Versions/A/$fw" "$work/sim_input"
done
install_name_tool -add_rpath /opt/homebrew/opt/axe/libexec/Frameworks "$work/sim_input"
install_name_tool -add_rpath /usr/local/opt/axe/libexec/Frameworks "$work/sim_input"
codesign --force -s - "$work/sim_input"

mkdir -p "$(dirname "$out")"
cp "$work/sim_input" "$out"
echo "Built $out"
