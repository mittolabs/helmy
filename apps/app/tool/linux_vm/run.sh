#!/usr/bin/env bash
# Builds Helmy for Linux in a container and runs it on a virtual screen.
#
#   tool/linux_vm/run.sh arm64|x64 build      build the release bundle
#   tool/linux_vm/run.sh arm64|x64 shot [s]   start it, wait s seconds (20),
#                                             save a screenshot, stop it
#
# Run from apps/app. x64 runs emulated (Rosetta), several times slower.
# Output lands in build/linux_vm/<arch>/: the bundle and shot.png.
set -euo pipefail
arch=${1:?arm64 or x64}
what=${2:?build or shot}
case $arch in
  arm64) platform=linux/arm64 ;;
  x64) platform=linux/amd64 ;;
  *) echo "arm64 or x64" >&2; exit 2 ;;
esac
here=$(cd "$(dirname "$0")" && pwd)
app=$(cd "$here/../.." && pwd)
image="helmy-linux:$arch"
out="$app/build/linux_vm/$arch"
mkdir -p "$out"
docker image inspect "$image" >/dev/null 2>&1 ||
  docker build --platform "$platform" -t "$image" "$here"
# The source is copied in, never built in place: the Mac's build folder stays the Mac's.
common=(--rm --platform "$platform" -v "$app:/src:ro" -v "$out:/out"
  -v "helmy-linux-pub-$arch:/root/.pub-cache" "$image")
case $what in
  build)
    docker run "${common[@]}" bash -c '
      set -e
      tar -C /src --exclude=./build --exclude=./.dart_tool -cf - . | tar -C /work -xf -
      cd /work && flutter pub get >/dev/null && flutter build linux --release
      rm -rf /out/bundle && cp -r build/linux/*/release/bundle /out/bundle
      echo "built: $(du -sh /out/bundle | cut -f1)"'
    ;;
  shot)
    wait=${3:-20}
    [ -x "$out/bundle/helmy" ] || { echo "no build: run '$0 $arch build' first" >&2; exit 1; }
    docker run "${common[@]}" bash -c "
      set -e
      export HOME=/tmp/home && mkdir -p \$HOME
      Xvfb :1 -screen 0 1440x900x24 >/dev/null 2>&1 & sleep 1
      export DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1
      dbus-launch --exit-with-session /out/bundle/helmy >/out/run.log 2>&1 & app=\$!
      sleep $wait
      if kill -0 \$app 2>/dev/null; then echo running; else echo 'exited:'; tail -20 /out/run.log; fi
      import -window root /out/shot.png && echo 'shot: build/linux_vm/$arch/shot.png'
      kill \$app 2>/dev/null || true"
    ;;
  *) echo "build or shot" >&2; exit 2 ;;
esac
