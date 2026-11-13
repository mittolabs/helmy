#!/usr/bin/env bash
# The site's pictures, made from the originals in art/: each one at the widths
# the page shows it at (and twice that, for sharp screens), as AVIF and WebP,
# into web/img/. The page offers both (lib/components/picture.dart) and the
# browser takes the first it can show. Run it again after changing art/ or a
# width here, and commit what it writes.
#
#   tool/images.sh        (needs sips, from macOS; cwebp; avifenc: brew install webp libavif)
set -euo pipefail
cd "$(dirname "$0")/.."

out=web/img
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
rm -rf "$out"
mkdir -p "$out"

# name  source  quality(webp)  quality(avif)  widths...
# Screenshots carry small text, so they keep more quality than Helmy's poses.
make() {
  local name=$1 src=$2 qw=$3 qa=$4
  shift 4
  for w in "$@"; do
    sips -s format png --resampleWidth "$w" "art/$src" --out "$tmp/$name.png" >/dev/null
    cwebp -quiet -q "$qw" -alpha_q 100 -m 6 -sharp_yuv "$tmp/$name.png" -o "$out/$name-$w.webp"
    avifenc -q "$qa" --qalpha 90 -s 2 -y 444 "$tmp/$name.png" "$out/$name-$w.avif" >/dev/null
  done
}

make chat chat.jpg 80 62 800 1200 1800
make design design.jpg 80 62 700 1400
make phone-chats phone-chats.jpg 80 62 322 644
make approval approval.jpg 80 62 560 1100

make hello-in hello-in.webp 85 60 240 480
make hello-out hello-out.webp 85 60 240 480
make hello-blink hello-blink.webp 85 60 240 480
make connect onboarding-connect.png 85 60 320 640
make folders onboarding-folders.png 85 60 320 640
make shield shield.png 85 60 320 640
make done onboarding-done.png 85 60 180 360
make hello hello.png 85 60 44 88
make icon icon.png 90 70 32 64 128

du -sh "$out"
