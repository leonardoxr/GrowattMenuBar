#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="GrowattMenuBar"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME.app"
INSTALL_DIR="${GROWATT_INSTALL_DIR:-$HOME/Applications}"
TARGET_APP="$INSTALL_DIR/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

"$ROOT_DIR/Scripts/build-app.sh"

mkdir -p "$INSTALL_DIR"

if pgrep -x "$APP_NAME" >/dev/null; then
  pkill -x "$APP_NAME" || true
  sleep 1
fi

rm -rf "$TARGET_APP"
/usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"

xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
"$LSREGISTER" -f "$TARGET_APP" 2>/dev/null || true

open "$TARGET_APP"

echo "Installed $TARGET_APP"
echo "You can now find GrowattMenuBar in Spotlight, Launchpad, or $INSTALL_DIR."
