# Helmy on Linux, to build and see: Flutter at the version CI uses, the
# libraries Helmy's plugins link, and a virtual screen to run it on.
FROM ubuntu:24.04
ARG FLUTTER_VERSION=3.47.5
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils zip file \
      clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev \
      xvfb xauth dbus-x11 x11-utils xdotool imagemagick \
      libgl1-mesa-dri libegl1 libgles2 mesa-utils fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH"
RUN git config --global --add safe.directory /opt/flutter \
    && flutter config --no-analytics --enable-linux-desktop \
    && flutter precache --linux
WORKDIR /work
