# Run from the repository root.
APP := apps/app
SITE := apps/site
DOCS := apps/docs
JASPR ?= $(HOME)/.pub-cache/bin/jaspr
DART ?= fvm dart

.PHONY: help setup app run chrome remote relay relay-image test live analyze format design-check design-check-flutter sim-input site site-dev docs docs-dev web local local-down deploy

help:
	@echo "make setup     the commit hook and dependencies"
	@echo "make app       debug build of the macOS app, signed when .signing.local names a certificate"
	@echo "make run       build it and open it"
	@echo "make chrome    Helmy in Chrome: build/chrome to load unpacked, and its zip"
	@echo "make remote    the page phones open in a browser, packed into the desktop app"
	@echo "make relay     Helmy Connect's relay on :8080, serving the phone page (build/connect)"
	@echo "make test      unit tests (no real agents, no usage)"
	@echo "make live      live tests against the real connections (costs usage)"
	@echo "make analyze   static analysis"
	@echo "make format    format the code (100 columns)"
	@echo "make design-check [DESIGN=folder]  a design exported to React, compared pixel by pixel"
	@echo "make design-check-flutter [DESIGN=folder]  exported to Flutter, each element where the page puts it"
	@echo "make sim-input rebuild the iOS simulator input helper (needs AXe and Xcode)"
	@echo "make site-dev  the site with hot reload on :8484"
	@echo "make site      release build of the site"
	@echo "make docs-dev  the docs with hot reload on :8485"
	@echo "make docs      release build of the docs"
	@echo "make web       helmy.ke in one folder: the site, and the docs under /docs/"
	@echo "make local     the release image served in Docker at http://localhost:8745"
	@echo "make deploy HOST=a [RELEASE=sha]   start a release CI built on the server"

setup:
	git config core.hooksPath .githooks
	cd $(APP) && fvm flutter pub get

app: remote
	cd $(APP) && fvm flutter build macos --debug --build-number=$$(git rev-list --count HEAD)
	cd $(APP) && tool/sign_mac.sh build/macos/Build/Products/Debug/Helmy.app

run: app
	open $(APP)/build/macos/Build/Products/Debug/Helmy.app

chrome:
	cd $(APP) && node tool/chrome.mjs

remote:
	cd $(APP) && node tool/remote.mjs

# Helmy Connect's relay, as connect.helmy.ke runs it: the page built first.
relay:
	cd $(APP) && node tool/remote.mjs --page
	cd apps/relay && PAGE=../app/build/connect $(DART) run bin/relay.dart

relay-image:
	cd $(APP) && node tool/remote.mjs --page
	docker build -f infra/relay.Dockerfile -t ghcr.io/mittolabs/helmy-relay:local .

test:
	cd $(APP) && fvm flutter test
	cd apps/relay && $(DART) test

live:
	cd $(APP) && fvm flutter test --tags live --run-skipped test/live_engines_test.dart

analyze:
	cd $(APP) && fvm dart analyze
	cd apps/cli && $(DART) analyze

format:
	cd $(APP) && fvm dart format lib test

# A design's export drawn beside the design, pixel by pixel (DESIGN=folder,
# the test design by default). CHROME=path uses a Chromium already there
# instead of downloading Playwright's.
DESIGN ?= test/fixtures/design
design-check:
	cd $(APP)/tool/design_check && npm install --silent && { [ -n "$$CHROME" ] || npx playwright install chromium; }
	cd $(APP) && rm -rf build/design-check && fvm dart run tool/design_export.dart $(DESIGN) build/design-check/react react
	cd $(APP) && node tool/design_check/check.mjs $(DESIGN) build/design-check/react build/design-check/out

# Each Flutter flavor (Ashlar, plain) exported with its elements keyed, laid
# out by Flutter at phone, tablet and desktop widths, and compared with where
# Chromium puts each one: all within TOLERANCE px (0.1 by default), or it fails.
design-check-flutter:
	cd $(APP)/tool/design_check && npm install --silent && { [ -n "$$CHROME" ] || npx playwright install chromium; }
	cd $(APP) && rm -rf build/design-check-flutter
	cd $(APP) && for f in flutter flutterPlain; do \
	  out=build/design-check-flutter/$$f; \
	  fvm dart run tool/design_export.dart $(DESIGN) $$out $$f --measure && \
	  (cd $$out && fvm flutter pub get >/dev/null && fvm flutter test test/measure_test.dart) && \
	  TOLERANCE=$${TOLERANCE:-0.1} node tool/design_check/flutter.mjs $(DESIGN) $$out || exit 1; \
	done

sim-input:
	$(APP)/tool/sim_input/build.sh

site-dev:
	cd $(SITE) && $(JASPR) serve

# The download page names the latest release's builds, read from GitHub: with
# GITHUB_TOKEN when there is one (anonymous reads are rate limited, and shared CI
# runners hit the limit). Here, without the releases the page says none is out
# yet; with RELEASES=required (the release image), the build fails instead, so
# a live page never loses its downloads.
site:
	curl -fsS $(if $(GITHUB_TOKEN),-H "Authorization: Bearer $(GITHUB_TOKEN)") 'https://api.github.com/repos/mittolabs/helmy/releases?per_page=20' > $(SITE)/.release.json \
		|| { [ "$(RELEASES)" = required ] && echo "Could not read the releases from GitHub" >&2 && exit 1; echo '{}' > $(SITE)/.release.json; }
	cd $(SITE) && $(JASPR) build

docs-dev:
	cd $(DOCS) && $(JASPR) serve --port 8485

docs:
	cd $(DOCS) && $(JASPR) build

web: site docs
	cd $(SITE) && $(DART) run tool/web.dart build/jaspr ../docs/build/jaspr build/web

# ── helmy.ke ──────────────────────────────────────────────────────────────────
# The release is one image, infra/Dockerfile: the site and docs inside the Caddy that
# serves them. CI builds it on every push to main that touches them
# (.github/workflows/site.yml). See infra/README.md.

local: relay-image
	docker build -f infra/Dockerfile -t ghcr.io/mittolabs/helmy-site:local .
	docker network inspect ashlar >/dev/null 2>&1 || docker network create ashlar
	docker compose -f infra/compose.yml up -d --wait --force-recreate

local-down:
	docker compose -f infra/compose.yml down

SSH_USER ?= deploy
SSH_PORT ?= 22
RELEASE ?= $(shell git rev-parse HEAD)
ANSIBLE := cd infra/ansible && HELMY_HOST=$(HOST) HELMY_SSH_PORT=$(SSH_PORT) HELMY_RELEASE=$(RELEASE) \
	GHCR_USER=$$(gh api user -q .login) GHCR_TOKEN=$$(gh auth token) \
	ansible-playbook -u $(SSH_USER) </dev/null

deploy:
	@test -n "$(HOST)" || { echo "Usage: make deploy HOST=<address> [RELEASE=<sha>]"; exit 1; }
	$(ANSIBLE) deploy.yml
