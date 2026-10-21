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
PLIST="build/Recall.app/Contents/Info.plist"
OBJ_DIR="build/obj"

# Determine if anything that goes into the bundle is newer than the existing signed binary.
# swiftc embeds non-deterministic UUIDs/timestamps, so recompiling always
# produces a different binary and therefore a new CDHash. macOS TCC ties
# screen-recording permission to the CDHash, meaning a new signature
# invalidates the grant. We avoid this by skipping compile+sign when
# nothing changed. A VERSION bump, a non-universal binary or FORCE_BUILD=1
# (used by release.sh) always rebuilds.
NEEDS_BUILD=true
if [ "${FORCE_BUILD:-0}" != "1" ] && [ -f "${BINARY}" ] && [ -f "${PLIST}" ]; then
    NEWEST_INPUT=$(find Sources/Recall VERSION scripts/build.sh -newer "${BINARY}" 2>/dev/null | head -n 1)
    BUILT_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${PLIST}" 2>/dev/null || echo "")
    BUILT_ARCHS=$(lipo -archs "${BINARY}" 2>/dev/null || echo "")
    if [ -z "${NEWEST_INPUT}" ] && [ "${BUILT_VERSION}" = "${VERSION}" ] &&
        [[ "${BUILT_ARCHS}" == *arm64* && "${BUILT_ARCHS}" == *x86_64* ]]; then
        NEEDS_BUILD=false
    fi
fi

if [ "${NEEDS_BUILD}" = true ]; then
    mkdir -p "${OBJ_DIR}"
    for ARCH in arm64 x86_64; do
        echo "==> Compiling Swift sources with swiftc (${ARCH})..."
        swiftc \
            -O \
            -wmo \
            -sdk "${SDK_PATH}" \
            -target "${ARCH}-apple-macos12.3" \
            -parse-as-library \
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
            Sources/Recall/*.swift \
            -o "${OBJ_DIR}/Recall-${ARCH}"
    done

    echo "==> Creating universal binary (arm64 + x86_64)..."
    lipo -create "${OBJ_DIR}/Recall-arm64" "${OBJ_DIR}/Recall-x86_64" -output "${BINARY}"

    echo "==> Writing Info.plist (v${VERSION})..."
    cat <<EOF >"${PLIST}"
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

    echo "==> Signing application bundle with ad-hoc signature and stable designated requirement..."
    codesign -s - --force --deep --options runtime -r='designated => identifier "com.recall.app"' build/Recall.app

    echo "==> Registering updated application icon with LaunchServices..."
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted build/Recall.app || true

    if [ -d "/Applications/Recall.app" ] && [ -w "/Applications/Recall.app" ]; then
        echo "==> Syncing /Applications/Recall.app..."
        rm -rf /Applications/Recall.app
        cp -R build/Recall.app /Applications/Recall.app
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted /Applications/Recall.app || true
    fi
else
    echo "==> Sources unchanged, skipping compile & codesign (preserving TCC permissions)."
fi

echo "==> Build successfully completed: build/Recall.app (v${VERSION})"
