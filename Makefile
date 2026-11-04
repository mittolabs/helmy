# Run from the repository root.
APP := apps/app

.PHONY: help setup app run test live analyze format

help:
	@echo "make setup     the commit hook and dependencies"
	@echo "make app       debug build of the macOS app"
	@echo "make run       build it and open it"
	@echo "make test      unit tests (no real agents, no usage)"
	@echo "make live      live tests against the real connections (costs usage)"
	@echo "make analyze   static analysis"
	@echo "make format    format the code (100 columns)"

setup:
	git config core.hooksPath .githooks
	cd $(APP) && fvm flutter pub get

app:
	cd $(APP) && fvm flutter build macos --debug --build-number=$(git rev-list --count HEAD)

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
