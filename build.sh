#!/usr/bin/env bash
set -euo pipefail

VERSION=$(tr -d ' \n\r' <VERSION 2>/dev/null || echo "1.0.0")

echo "==> Building Recall.app v${VERSION}..."

mkdir -p build/Recall.app/Contents/MacOS
mkdir -p build/Recall.app/Contents/Resources

if [ -f "Resources/AppIcon.png" ]; then
    echo "==> Copying AppIcon.png from Resources..."
    cp Resources/AppIcon.png build/Recall.app/Contents/Resources/
fi

if [ -f "Resources/AppIcon.icns" ]; then
    echo "==> Copying AppIcon.icns from Resources..."
    cp Resources/AppIcon.icns build/Recall.app/Contents/Resources/
fi

SDK_PATH=$(xcrun --show-sdk-path)

BINARY="build/Recall.app/Contents/MacOS/Recall"

# Determine if any source files are newer than the existing signed binary.
# swiftc embeds non-deterministic UUIDs/timestamps, so recompiling always
# produces a different binary and therefore a new CDHash. macOS TCC ties
# screen-recording permission to the CDHash, meaning a new signature
# invalidates the grant. We avoid this by skipping compile+sign when
# the sources haven't changed.
NEEDS_BUILD=true
if [ -f "${BINARY}" ]; then
    NEWEST_SOURCE=$(find Sources/Recall -name '*.swift' -newer "${BINARY}" 2>/dev/null | head -n 1)
    if [ -z "${NEWEST_SOURCE}" ]; then
        NEEDS_BUILD=false
    fi
fi

if [ "${NEEDS_BUILD}" = true ]; then
    echo "==> Compiling Swift sources with swiftc..."
    swiftc \
        -O \
        -sdk "${SDK_PATH}" \
        -target x86_64-apple-macos12.3 \
        -parse-as-library \
        -framework ScreenCaptureKit \
        -framework AVFoundation \
        -framework SwiftUI \
        -framework AppKit \
        -framework CoreMedia \
        -framework CoreVideo \
        -framework CoreGraphics \
        -framework UniformTypeIdentifiers \
        Sources/Recall/*.swift \
        -o "${BINARY}"

    echo "==> Signing application bundle with ad-hoc signature..."
    codesign -s - --force --deep --options runtime build/Recall.app

    echo "==> Registering updated application icon with LaunchServices..."
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted build/Recall.app || true
    touch build/Recall.app
else
    echo "==> Sources unchanged, skipping compile & codesign (preserving TCC permissions)."
fi

echo "==> Writing Info.plist (v${VERSION})..."
cat <<EOF >build/Recall.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Recall</string>
    <key>CFBundleIdentifier</key>
    <string>com.recall.app</string>
    <key>CFBundleName</key>
    <string>Recall</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.3</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Recall requires screen capture permission to record full display video.</string>
</dict>
</plist>
EOF

echo "==> Build successfully completed: build/Recall.app (v${VERSION})"
