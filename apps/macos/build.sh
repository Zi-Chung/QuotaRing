#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
APP_NAME="QuotaRing.app"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
RESOURCES_DIR="${APP_BUNDLE}/Contents/Resources"
VERSION="${QUOTARING_VERSION:-1.0.0}"
UNIVERSAL=false

if [[ "${1:-}" == "--universal" ]]; then
  UNIVERSAL=true
fi

SOURCES=(
  "${SCRIPT_DIR}/Sources/QuotaFetcher.swift"
  "${SCRIPT_DIR}/Sources/FileWatcher.swift"
  "${SCRIPT_DIR}/Sources/GlobalHotKey.swift"
  "${SCRIPT_DIR}/Sources/PopoverView.swift"
  "${SCRIPT_DIR}/Sources/AppDelegate.swift"
  "${SCRIPT_DIR}/Sources/main.swift"
)

echo "==> Cleaning build directory..."
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

MODULE_CACHE="/tmp/quotaring-module-cache"
mkdir -p "${MODULE_CACHE}"

if [[ "${UNIVERSAL}" == "true" ]]; then
  echo "==> Compiling Universal Binary (arm64 + x86_64)..."
  swiftc -O -module-cache-path "${MODULE_CACHE}" \
    -target arm64-apple-macosx13.0 -framework Cocoa -framework SwiftUI -framework Carbon \
    "${SOURCES[@]}" -o "${BUILD_DIR}/QuotaRing-arm64"
  swiftc -O -module-cache-path "${MODULE_CACHE}" \
    -target x86_64-apple-macosx13.0 -framework Cocoa -framework SwiftUI -framework Carbon \
    "${SOURCES[@]}" -o "${BUILD_DIR}/QuotaRing-x86_64"
  lipo -create \
    "${BUILD_DIR}/QuotaRing-arm64" \
    "${BUILD_DIR}/QuotaRing-x86_64" \
    -output "${MACOS_DIR}/QuotaRing"
  rm -f "${BUILD_DIR}/QuotaRing-arm64" "${BUILD_DIR}/QuotaRing-x86_64"
else
  HOST_ARCH="$(uname -m)"
  echo "==> Compiling for ${HOST_ARCH}..."
  swiftc -O -module-cache-path "${MODULE_CACHE}" \
    -target "${HOST_ARCH}-apple-macosx13.0" -framework Cocoa -framework SwiftUI -framework Carbon \
    "${SOURCES[@]}" -o "${MACOS_DIR}/QuotaRing"
fi

echo "==> Writing Info.plist (v${VERSION})..."
cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>QuotaRing</string>
    <key>CFBundleIdentifier</key>
    <string>com.quotaring.app</string>
    <key>CFBundleName</key>
    <string>QuotaRing</string>
    <key>CFBundleDisplayName</key>
    <string>QuotaRing</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "==> Ad-hoc code signing..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> Built: ${APP_BUNDLE}"
