#!/usr/bin/env bash
set -euo pipefail

echo "==> Compiling test runner with code coverage instrumentation..."
mkdir -p build/cov

SDK_PATH=$(xcrun --show-sdk-path)
SOURCES=$(find Sources/Recall -name '*.swift')
TEST_SOURCES=$(find Tests/RecallTests -name '*.swift')

swiftc \
    -DTEST_RUNNER \
    -profile-generate \
    -profile-coverage-mapping \
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
    -o build/cov/test_runner_cov

echo "==> Running instrumented test suite..."
LLVM_PROFILE_FILE="build/cov/default.profraw" build/cov/test_runner_cov >/dev/null 2>&1 || true

echo "==> Generating Code Coverage Report..."
xcrun llvm-profdata merge -sparse build/cov/default.profraw -o build/cov/default.profdata
xcrun llvm-cov report build/cov/test_runner_cov -instr-profile=build/cov/default.profdata Sources/Recall/*.swift
