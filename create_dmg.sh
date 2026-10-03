#!/usr/bin/env bash
set -euo pipefail

VERSION=$(tr -d ' \n\r' <VERSION 2>/dev/null || echo "1.0.0")
VOLNAME="Recall ${VERSION}"
DMG_NAME="Recall-v${VERSION}.dmg"
TEMP_DMG="build/pack_temp.dmg"
FINAL_DMG="build/${DMG_NAME}"

echo "==> Packaging ${DMG_NAME} with custom layout..."

# 1. Ensure build/Recall.app exists
if [ ! -d "build/Recall.app" ]; then
    ./build.sh
fi

# 2. Ensure background image exists and is compiled
echo "==> Generating DMG background image..."
swiftc Resources/create_dmg_background.swift -o build/gen_bg
build/gen_bg Resources/dmg_background.png

# 3. Clean up old build artifacts & mounts
rm -f "${TEMP_DMG}" "${FINAL_DMG}"
hdiutil detach "/Volumes/${VOLNAME}" -force 2>/dev/null || true

# 4. Create read-write temporary DMG
echo "==> Creating temporary disk image..."
hdiutil create -size 120m -fs HFS+ -volname "${VOLNAME}" "${TEMP_DMG}"

# 5. Mount temporary DMG
echo "==> Mounting temporary disk image..."
MOUNT_INFO=$(hdiutil attach -nobrowse -readwrite "${TEMP_DMG}")
MOUNT_DIR=$(echo "${MOUNT_INFO}" | grep "/Volumes/" | awk -F '\t' '{print $NF}')

echo "Mounted at: ${MOUNT_DIR}"

# 6. Copy files to volume
echo "==> Copying Recall.app and setting up volume..."
cp -R build/Recall.app "${MOUNT_DIR}/"
ln -s /Applications "${MOUNT_DIR}/Applications"

mkdir -p "${MOUNT_DIR}/.background"
cp Resources/dmg_background.png "${MOUNT_DIR}/.background/background.png"

# Hide background directory
SetFile -a V "${MOUNT_DIR}/.background" 2>/dev/null || true

# 7. Apply Finder window layout via AppleScript
echo "==> Styling Finder window layout..."
osascript <<EOF
tell application "Finder"
    tell disk "${VOLNAME}"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set the bounds of container window to {350, 150, 1090, 570}
        
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 110
        
        try
            set background picture of viewOptions to file ".background:background.png"
        on error err
            log "Failed relative picture path: " & err
            try
                set background picture of viewOptions to (POSIX file "${MOUNT_DIR}/.background/background.png" as alias)
            on error err2
                log "Failed absolute picture path: " & err2
            end try
        end try
        
        set position of item "Recall.app" of container window to {200, 190}
        set position of item "Applications" of container window to {540, 190}
        
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
EOF

sync

# 8. Unmount temporary DMG
echo "==> Unmounting temporary disk image..."
hdiutil detach "${MOUNT_DIR}" -force || hdiutil detach "/Volumes/${VOLNAME}" -force

# 9. Convert to final compressed DMG
echo "==> Compressing final DMG..."
hdiutil convert "${TEMP_DMG}" -format UDZO -imagekey zlib-level=9 -o "${FINAL_DMG}" -ov

# 10. Clean up temporary files
rm -f "${TEMP_DMG}"

echo "==> DMG successfully created with custom graphics: ${FINAL_DMG}"
