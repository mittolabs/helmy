# Run from the repository root.
APP := apps/app
SITE := apps/site
DOCS := apps/docs
JASPR ?= $(HOME)/.pub-cache/bin/jaspr

.PHONY: help setup app run test live analyze format sim-input site site-dev docs docs-dev

help:
	@echo "make setup     the commit hook and dependencies"
	@echo "make app       debug build of the macOS app, signed when .signing.local names a certificate"
	@echo "make run       build it and open it"
	@echo "make test      unit tests (no real agents, no usage)"
	@echo "make live      live tests against the real connections (costs usage)"
	@echo "make analyze   static analysis"
	@echo "make format    format the code (100 columns)"
	@echo "make sim-input rebuild the iOS simulator input helper (needs AXe and Xcode)"
	@echo "make site-dev  the site with hot reload on :8484"
	@echo "make site      release build of the site"
	@echo "make docs-dev  the docs with hot reload on :8485"
	@echo "make docs      release build of the docs"

setup:
	git config core.hooksPath .githooks
	cd $(APP) && fvm flutter pub get

app:
	cd $(APP) && fvm flutter build macos --debug --build-number=$$(git rev-list --count HEAD)
	cd $(APP) && tool/sign_mac.sh build/macos/Build/Products/Debug/Helmy.app

run: app
	open $(APP)/build/macos/Build/Products/Debug/Helmy.app

test:
	cd $(APP) && fvm flutter test

live:
	cd $(APP) && fvm flutter test --tags live --run-skipped test/live_engines_test.dart

analyze:
	cd $(APP) && fvm dart analyze

format:
	cd $(APP) && fvm dart format lib test

sim-input:
	$(APP)/tool/sim_input/build.sh

site-dev:
	cd $(SITE) && $(JASPR) serve

site:
	gh api repos/mittolabs/helmy/releases/latest > $(SITE)/.release.json 2>/dev/null || echo '{}' > $(SITE)/.release.json
	cd $(SITE) && $(JASPR) build

docs-dev:
	cd $(DOCS) && $(JASPR) serve --port 8485

docs:
	cd $(DOCS) && $(JASPR) build
