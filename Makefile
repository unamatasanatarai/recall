.DEFAULT_GOAL := help

.PHONY: help build test coverage dmg release run launch revoke clean

## help: Display this help message
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@awk '/^##/ { printf "  \033[36m%-15s\033[0m %s\n", substr($$2, 1, length($$2)-1), substr($$0, index($$0, $$3)) }' $(MAKEFILE_LIST)

## build: Compile Recall.app and sign binary
build:
	@./build.sh

## test: Run unit test suite
test:
	@./test.sh

## coverage: Run unit test suite and display code coverage report
coverage:
	@./coverage.sh

## dmg: Build Recall.app and package into a pretty compressed .dmg file
dmg: build
	@./create_dmg.sh

## release: Create version bump, generate release notes, tag git, build DMG, and publish GitHub release
release:
	@./release.sh $(VERSION)



## run: Launch compiled Recall.app
run: build
	@echo "==> Launching Recall.app..."
	@open build/Recall.app

## revoke: Reset macOS ScreenCapture TCC permissions for com.recall.app
revoke:
	@echo "==> Resetting ScreenCapture TCC permission..."
	@tccutil reset ScreenCapture com.recall.app || true

## launch: Open Recall.app without rebuilding (preserves TCC CDHash)
launch:
	@echo "==> Launching Recall.app (no rebuild)..."
	@open build/Recall.app

## clean: Remove build artifacts
clean:
	@echo "==> Cleaning build artifacts..."
	@rm -rf build

