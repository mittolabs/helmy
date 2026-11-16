# Helmy Connect's relay (apps/relay), with the phone page it serves at connect.helmy.ke:
# one small image, no shell. The page is built beforehand, on the runner, by
# `node tool/remote.mjs --page` in apps/app (apps/app/build/connect).
#
#   docker build -f infra/relay.Dockerfile -t helmy-relay .
#
# Compiled once on the build machine for the image's platform (Dart cross-compiles), so
# an arm64 image needs no emulation. CI builds it beside the site (.github/workflows/site.yml).

FROM --platform=$BUILDPLATFORM dart:3.13.4 AS build
ARG TARGETARCH
WORKDIR /src
COPY apps/relay/pubspec.yaml apps/relay/pubspec.lock apps/relay/
RUN cd apps/relay && dart pub get
COPY apps/relay apps/relay
# Again after the copy: a .dart_tool from the build machine came with it, naming its paths.
RUN cd apps/relay && rm -rf .dart_tool && dart pub get --offline && dart compile exe bin/relay.dart -o /relay \
    --target-os=linux --target-arch=$([ "$TARGETARCH" = arm64 ] && echo arm64 || echo x64)

# The runtime libraries a Dart program needs, for the image's own platform.
FROM dart:3.13.4 AS runtime

FROM scratch
COPY --from=runtime /runtime/ /
COPY --from=build /relay /app/relay
COPY apps/app/build/connect /page
ENV PORT=8080 PAGE=/page
EXPOSE 8080
LABEL org.opencontainers.image.source=https://github.com/mittolabs/helmy
ENTRYPOINT ["/app/relay"]
