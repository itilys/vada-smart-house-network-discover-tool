#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="VaDa Network Discover"
DIST_APP="$ROOT_DIR/dist/${APP_NAME}.app"
INSTALL_DIR="$HOME/Applications"
INSTALL_APP="$INSTALL_DIR/${APP_NAME}.app"

if [[ ! -d "$DIST_APP" ]]; then
  "$ROOT_DIR/scripts/build_app_bundle.sh" >/dev/null
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_APP"
ditto --norsrc "$DIST_APP" "$INSTALL_APP"

echo "$INSTALL_APP"
