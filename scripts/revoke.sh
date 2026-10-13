#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

APP_NAME="${APP_NAME:-Recall}"
BUNDLE_ID="${BUNDLE_ID:-com.recall.app}"

echo "==> Terminating existing ${APP_NAME} instances..."
killall "${APP_NAME}" 2>/dev/null || pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 0.2

echo "==> Revoking all macOS permissions for ${APP_NAME} (${BUNDLE_ID})..."

# List of all relevant TCC permissions for Recall and screen/system capture
SERVICES=(
    "ScreenCapture"
    "Accessibility"
    "Microphone"
    "Camera"
    "SystemPolicyAllFiles"
    "All"
)

for service in "${SERVICES[@]}"; do
    echo "  -> Revoking ${service}..."
    tccutil reset "${service}" "${BUNDLE_ID}" 2>/dev/null || true
done

echo "✅ All permissions successfully revoked for ${BUNDLE_ID}."
