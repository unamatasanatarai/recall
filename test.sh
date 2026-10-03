#!/usr/bin/env bash
set -euo pipefail

echo "==> Compiling unit test runner..."
mkdir -p build

SDK_PATH=$(xcrun --show-sdk-path)
SOURCES=$(find Sources/Recall -name '*.swift')
TEST_SOURCES=$(find Tests/RecallTests -name '*.swift')

swiftc \
    -DTEST_RUNNER \
    -sdk "${SDK_PATH}" \
    -target x86_64-apple-macos12.3 \
    -framework ScreenCaptureKit \
    -framework AVFoundation \
    -framework SwiftUI \
    -framework AppKit \
    -framework CoreMedia \
    -framework CoreVideo \
    -framework CoreGraphics \
    -framework UniformTypeIdentifiers \
    ${SOURCES} \
    ${TEST_SOURCES} \
    -o build/test_runner

echo "==> Running unit tests..."
build/test_runner
