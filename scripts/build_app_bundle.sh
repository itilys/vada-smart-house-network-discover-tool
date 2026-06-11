#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="VaDa Network Discover"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
DIST_APP="$DIST_DIR/${APP_NAME}.app"
DIST_ZIP="$DIST_DIR/VaDa-Network-Discover-macOS.zip"
TMP_DIR="$(mktemp -d)"
TMP_APP="$TMP_DIR/${APP_NAME}.app"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

clean_bundle_metadata() {
  local bundle="$1"

  xattr -cr "$bundle" 2>/dev/null || true
  xattr -dr com.apple.FinderInfo "$bundle" 2>/dev/null || true
  xattr -dr 'com.apple.fileprovider.fpfs#P' "$bundle" 2>/dev/null || true
}

swift build --disable-sandbox -c release --product NetworkDiscoverApp

rm -rf "$TMP_APP"
mkdir -p "$TMP_APP/Contents/MacOS" "$TMP_APP/Contents/Resources"
cp "$BUILD_DIR/NetworkDiscoverApp" "$TMP_APP/Contents/MacOS/NetworkDiscoverApp"

ICON_WORK="$TMP_DIR/icons"
swift "$ROOT_DIR/scripts/generate_app_icons.swift" "$ICON_WORK"
if ! iconutil -c icns "$ICON_WORK/AppIcon.iconset" -o "$TMP_APP/Contents/Resources/AppIcon.icns" >/dev/null 2>&1; then
  TIFF_WORK="$TMP_DIR/icon-tiffs"
  mkdir -p "$TIFF_WORK"
  for icon in "$ICON_WORK/AppIcon.iconset/"*.png; do
    sips -s format tiff "$icon" --out "$TIFF_WORK/$(basename "${icon%.png}").tiff" >/dev/null
  done
  tiffutil -cat "$TIFF_WORK/"*.tiff -out "$ICON_WORK/AppIcon.tiff" >/dev/null 2>&1
  tiff2icns "$ICON_WORK/AppIcon.tiff" "$TMP_APP/Contents/Resources/AppIcon.icns" >/dev/null 2>&1
fi

cat > "$TMP_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>NetworkDiscoverApp</string>
  <key>CFBundleIdentifier</key>
  <string>com.vadasmarthouse.networkdiscover</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSLocalNetworkUsageDescription</key>
  <string>VaDa Network Discover escanea segmentos de red locales autorizados para mostrar equipos y puertos abiertos.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

printf "APPL????" > "$TMP_APP/Contents/PkgInfo"

clean_bundle_metadata "$TMP_APP"
codesign --force --deep --sign - "$TMP_APP" >/dev/null 2>&1 || true

rm -rf "$DIST_APP" "$DIST_ZIP" "$DIST_DIR/Network Discover.app" "$DIST_DIR/NetworkDiscover-macOS.zip"
mkdir -p "$DIST_DIR"
ditto --norsrc "$TMP_APP" "$DIST_APP"
clean_bundle_metadata "$DIST_APP"
codesign --force --deep --sign - "$DIST_APP" >/dev/null 2>&1 || true
ditto -c -k --norsrc --keepParent "$DIST_APP" "$DIST_ZIP"
clean_bundle_metadata "$DIST_APP"
codesign --force --deep --sign - "$DIST_APP" >/dev/null 2>&1 || true

echo "$DIST_APP"
echo "$DIST_ZIP"
