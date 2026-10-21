.DEFAULT_GOAL := help
.PHONY: help build run launch test test-tsan coverage clean reset-cache install dmg release release-dry-run kill revoke

# Load configurations dynamically from scripts/config.sh or environment
APP_NAME ?= $(shell bash -c 'source scripts/config.sh 2>/dev/null && echo "$$APP_NAME"' 2>/dev/null)
ifeq ($(strip $(APP_NAME)),)
  APP_NAME := Recall
endif
BUNDLE_ID ?= $(shell bash -c 'source scripts/config.sh 2>/dev/null && echo "$$BUNDLE_ID"' 2>/dev/null)
ifeq ($(strip $(BUNDLE_ID)),)
  BUNDLE_ID := com.recall.app
endif

## help: Display this help message
help:
	@echo "Usage: make [target] [VERSION=x.y.z]"
	@echo ""
	@echo "Targets:"
	@awk '/^##/ { printf "  \033[36m%-20s\033[0m %s\n", substr($$2, 1, length($$2)-1), substr($$0, index($$0, $$3)) }' $(MAKEFILE_LIST)

## build: Compile $(APP_NAME).app and sign bundle
build:
	@./scripts/build.sh

## run: Launch compiled $(APP_NAME).app
run: kill build
	@echo "==> Launching $(APP_NAME).app..."
	@open "build/$(APP_NAME).app"

## launch: Open $(APP_NAME).app without rebuilding
launch: kill
	@echo "==> Launching $(APP_NAME).app (no rebuild)..."
	@open "build/$(APP_NAME).app"

## kill: Quit running $(APP_NAME) instances (waits while they save the current chunk)
kill:
	@echo "==> Terminating existing $(APP_NAME) instances..."
	@killall "$(APP_NAME)" 2>/dev/null || pkill -x "$(APP_NAME)" 2>/dev/null || true
	@for i in $$(seq 1 80); do pgrep -x "$(APP_NAME)" >/dev/null || exit 0; sleep 0.1; done; \
		echo "⚠️  $(APP_NAME) is still running"

## test: Run native Swift unit test suite
test:
	@./scripts/test.sh

## test-tsan: Run the unit test suite under ThreadSanitizer
test-tsan:
	@SANITIZE=thread ./scripts/test.sh

## coverage: Print a code coverage report for the unit test suite
coverage:
	@./scripts/coverage.sh

## reset-cache: Clear macOS LaunchServices and IconServices caches
reset-cache:
	@echo "==> Resetting macOS Icon and LaunchServices caches..."
	@touch "build/$(APP_NAME).app" 2>/dev/null || true
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R "build/$(APP_NAME).app" 2>/dev/null || true
	@qlmanage -r 2>/dev/null || true
	@qlmanage -r cache 2>/dev/null || true
	@killall Dock 2>/dev/null || true
	@echo "✅ Cache reset complete."

## revoke: Terminate running app and revoke all macOS TCC permissions for $(APP_NAME)
revoke: kill
	@./scripts/revoke.sh

## clean: Remove build artifacts and temporary files
clean:
	@echo "==> Cleaning build artifacts..."
	@rm -rf build .build /tmp/RunSwiftTests*
	@echo "✅ Clean complete."

## install: Install $(APP_NAME).app to /Applications
install: build
	@echo "==> Installing $(APP_NAME).app to /Applications..."
	@rm -rf "/Applications/$(APP_NAME).app"
	@cp -R "build/$(APP_NAME).app" /Applications/
	@echo "✅ Installed to /Applications/$(APP_NAME).app"

## dmg: Create DMG installer package with custom styled background
dmg: build
	@./scripts/build_dmg.sh

# Capture positional version argument for release targets (e.g. make release 1.1.0)
ifeq ($(firstword $(MAKECMDGOALS)),$(filter $(firstword $(MAKECMDGOALS)),release release-dry-run))
  RELEASE_TARGET_VERSION := $(word 2,$(MAKECMDGOALS))
  ifneq ($(RELEASE_TARGET_VERSION),)
    $(eval $(RELEASE_TARGET_VERSION):;@:)
  endif
endif

## release-dry-run: Preview release tagging and publishing (e.g. make release-dry-run [version])
release-dry-run:
	@./scripts/release.sh --dry-run $(if $(VERSION),$(VERSION),$(RELEASE_TARGET_VERSION))

## release: Bump version (auto or specified: make release [version]), build DMG, tag & publish
release:
	@./scripts/release.sh $(if $(VERSION),$(VERSION),$(RELEASE_TARGET_VERSION))
