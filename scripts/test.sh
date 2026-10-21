#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/test.sh [name-filter]
#   SANITIZE=thread scripts/test.sh   runs the suite under ThreadSanitizer

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/generate_test_registry.sh"

echo "==> Compiling unit test runner..."
mkdir -p build

SDK_PATH=$(xcrun --show-sdk-path)
SOURCES=$(find Sources/Recall -name '*.swift')
TEST_SOURCES=$(find Tests/RecallTests -name '*.swift')
RUNNER="build/test_runner"
EXTRA_FLAGS=()
if [ -n "${SANITIZE:-}" ]; then
    EXTRA_FLAGS+=("-sanitize=${SANITIZE}")
    RUNNER="build/test_runner_${SANITIZE}"
fi

swiftc \
    -DTEST_RUNNER \
    -sdk "${SDK_PATH}" \
    -target "$(uname -m)-apple-macos12.3" \
    ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} \
    -framework ScreenCaptureKit \
    -framework AVFoundation \
    -framework SwiftUI \
    -framework AppKit \
    -framework CoreMedia \
    -framework CoreVideo \
    -framework CoreGraphics \
    -framework IOSurface \
    -framework VideoToolbox \
    -framework ServiceManagement \
    -framework UserNotifications \
    ${SOURCES} \
    ${TEST_SOURCES} \
    build/generated/TestRegistry.swift \
    -o "${RUNNER}"

echo "==> Running unit tests..."
if [ "${SANITIZE:-}" = "thread" ]; then
    LOG="build/tsan_output.txt"
    set +e
    TSAN_OPTIONS="${TSAN_OPTIONS:-halt_on_error=0 second_deadlock_stack=1}" "${RUNNER}" "$@" 2>&1 | tee "${LOG}"
    STATUS=${PIPESTATUS[0]}
    set -e
    if grep -q "WARNING: ThreadSanitizer" "${LOG}"; then
        echo "❌ ThreadSanitizer reported $(grep -c 'WARNING: ThreadSanitizer' "${LOG}") issue(s); see ${LOG}"
        exit 1
    fi
    exit "${STATUS}"
fi
"${RUNNER}" "$@"
