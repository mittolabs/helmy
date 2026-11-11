# The release of helmy.ke: the site and the docs, built from one commit, inside the Caddy
# that serves them. One image is everything a server needs besides infra/compose.yml.
#
#   docker build -f infra/Dockerfile -t helmy-site .
#
# CI builds it on every push to main that touches the site, the docs or the changelog, and
# after each release's builds are attached (.github/workflows/site.yml). See README.md here.

FROM --platform=$BUILDPLATFORM dart:3.13.4 AS build
RUN apt-get update && apt-get install -y --no-install-recommends make curl && rm -rf /var/lib/apt/lists/*
RUN dart pub global activate jaspr_cli 0.23.4
WORKDIR /src
COPY apps/site/pubspec.yaml apps/site/pubspec.lock apps/site/
COPY apps/docs/pubspec.yaml apps/docs/pubspec.lock apps/docs/
RUN cd apps/site && dart pub get && cd ../docs && dart pub get
COPY Makefile CHANGELOG.md ./
COPY apps/site apps/site
COPY apps/docs apps/docs
# make site reads the latest release from GitHub, so the download page names its builds.
RUN make web JASPR=/root/.pub-cache/bin/jaspr DART=dart

FROM caddy:2.11.4-alpine
COPY infra/Caddyfile /etc/caddy/Caddyfile
COPY --from=build /src/apps/site/build/web /srv/site
ARG RELEASE=local
RUN echo "$RELEASE" > /srv/site/release.txt
LABEL org.opencontainers.image.source=https://github.com/mittolabs/helmy
