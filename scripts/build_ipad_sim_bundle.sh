#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="VaDa Network Discover iPad"
SCRATCH_DIR="$ROOT_DIR/.build-ios"
DIST_DIR="$ROOT_DIR/dist-ios-sim"
DIST_APP="$DIST_DIR/${APP_NAME}.app"
SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
ICON_WORK="$(mktemp -d)"

cleanup() {
  rm -rf "$ICON_WORK"
}
trap cleanup EXIT

case "$(uname -m)" in
  arm64) TRIPLE="${TRIPLE:-arm64-apple-ios17.0-simulator}" ;;
  *) TRIPLE="${TRIPLE:-x86_64-apple-ios17.0-simulator}" ;;
esac

swift build \
  --disable-sandbox \
  --scratch-path "$SCRATCH_DIR" \
  --sdk "$SDK_PATH" \
  --triple "$TRIPLE" \
  --product NetworkDiscoverApp

BIN_DIR="$(swift build \
  --disable-sandbox \
  --scratch-path "$SCRATCH_DIR" \
  --sdk "$SDK_PATH" \
  --triple "$TRIPLE" \
  --show-bin-path)"

rm -rf "$DIST_APP"
mkdir -p "$DIST_APP"
cp "$BIN_DIR/NetworkDiscoverApp" "$DIST_APP/NetworkDiscoverApp"

swift "$ROOT_DIR/scripts/generate_app_icons.swift" "$ICON_WORK"
cp "$ICON_WORK/ios/"*.png "$DIST_APP/"

cat > "$DIST_APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>NetworkDiscoverApp</string>
  <key>CFBundleIdentifier</key>
  <string>com.vadasmarthouse.networkdiscover.ipad</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>VaDa Network Discover</string>
  <key>CFBundleIcons</key>
  <dict>
    <key>CFBundlePrimaryIcon</key>
    <dict>
      <key>CFBundleIconFiles</key>
      <array>
        <string>AppIcon-76</string>
        <string>AppIcon-76@2x</string>
        <string>AppIcon-83.5@2x</string>
      </array>
      <key>UIPrerenderedIcon</key>
      <false/>
    </dict>
  </dict>
  <key>CFBundleIcons~ipad</key>
  <dict>
    <key>CFBundlePrimaryIcon</key>
    <dict>
      <key>CFBundleIconFiles</key>
      <array>
        <string>AppIcon-76</string>
        <string>AppIcon-76@2x</string>
        <string>AppIcon-83.5@2x</string>
      </array>
      <key>UIPrerenderedIcon</key>
      <false/>
    </dict>
  </dict>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSRequiresIPhoneOS</key>
  <true/>
  <key>NSLocalNetworkUsageDescription</key>
  <string>VaDa Network Discover escanea redes locales autorizadas para mostrar equipos y puertos abiertos.</string>
  <key>UIDeviceFamily</key>
  <array>
    <integer>2</integer>
  </array>
  <key>UILaunchScreen</key>
  <dict/>
  <key>UISupportedInterfaceOrientations~ipad</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationPortraitUpsideDown</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
</dict>
</plist>
PLIST

xattr -cr "$DIST_APP" 2>/dev/null || true
xattr -d com.apple.FinderInfo "$DIST_APP" 2>/dev/null || true
xattr -d com.apple.fileprovider.fpfs#P "$DIST_APP" 2>/dev/null || true
codesign --force --deep --sign - "$DIST_APP" >/dev/null 2>&1 || true

echo "$DIST_APP"
