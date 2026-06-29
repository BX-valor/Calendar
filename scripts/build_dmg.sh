#!/bin/bash
set -euo pipefail

# ConferenceDeadline macOS .dmg packager
# Usage: ./scripts/build_dmg.sh

VERSION="1.4"
APP_NAME="ConferenceDeadline"
BUNDLE_ID="com.bxvalor.conference-deadline"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"
RELEASE_DIR="${BUILD_DIR}/release"
APP_BUNDLE="${RELEASE_DIR}/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"

echo "==> Building ${APP_NAME} v${VERSION}..."

# Clean previous build
rm -rf "${BUILD_DIR}"
mkdir -p "${RELEASE_DIR}"

# Build release executable
cd "${PROJECT_ROOT}"
swift build -c release

EXECUTABLE_SOURCE="${PROJECT_ROOT}/.build/release/${APP_NAME}"
if [[ ! -f "${EXECUTABLE_SOURCE}" ]]; then
    echo "Error: release executable not found at ${EXECUTABLE_SOURCE}"
    exit 1
fi

# Create .app bundle structure
echo "==> Assembling ${APP_NAME}.app bundle..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${EXECUTABLE_SOURCE}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Generate app icon .icns from Assets.xcassets
ICONSET_DIR="${BUILD_DIR}/AppIcon.iconset"
ICNS_PATH="${BUILD_DIR}/AppIcon.icns"
ASSETS_SOURCE="${PROJECT_ROOT}/Sources/${APP_NAME}/Resources/Assets.xcassets/AppIcon.appiconset"

if [[ -d "${ASSETS_SOURCE}" ]]; then
    rm -rf "${ICONSET_DIR}"
    mkdir -p "${ICONSET_DIR}"
    for size in 16 32 128 256 512; do
        cp "${ASSETS_SOURCE}/icon_${size}x${size}.png" "${ICONSET_DIR}/"
        cp "${ASSETS_SOURCE}/icon_${size}x${size}@2x.png" "${ICONSET_DIR}/"
    done
    iconutil -c icns "${ICONSET_DIR}" -o "${ICNS_PATH}"
    cp "${ICNS_PATH}" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# Generate Info.plist
cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
</dict>
</plist>
EOF

# Ad-hoc sign the app
echo "==> Ad-hoc signing ${APP_NAME}.app..."
codesign --sign - --force --deep --verbose "${APP_BUNDLE}"

# Verify create-dmg is installed
if ! command -v create-dmg &> /dev/null; then
    echo "Error: create-dmg is not installed. Install it with:"
    echo "  brew install create-dmg"
    exit 1
fi

# Create .dmg
echo "==> Creating ${DMG_NAME}..."
create-dmg \
    --volname "${APP_NAME} Installer" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --app-drop-link 450 185 \
    "${DMG_PATH}" \
    "${APP_BUNDLE}"

echo ""
echo "==> Done! Output: ${DMG_PATH}"
