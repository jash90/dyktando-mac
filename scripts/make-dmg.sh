#!/usr/bin/env bash
set -euo pipefail

ARCHIVE="$1"
OUT_DIR="${2:-build}"
APP_PATH="$ARCHIVE/Products/Applications/Dyktando.app"
DMG_PATH="$OUT_DIR/Dyktando.dmg"

if [ ! -d "$APP_PATH" ]; then
  echo "Error: Dyktando.app not found at $APP_PATH" >&2
  exit 1
fi

# Ad-hoc sign (no Developer ID required) — needed so AppleScript / Accessibility
# permissions stick across launches.
echo "Code-signing $APP_PATH (ad-hoc)…"
codesign --force --deep --sign - "$APP_PATH"

# Remove existing DMG.
rm -f "$DMG_PATH"

# Build the DMG. Prefer create-dmg if installed, otherwise hdiutil.
if command -v create-dmg >/dev/null 2>&1; then
  echo "Using create-dmg…"
  cd "$(dirname "$DMG_PATH")"
  create-dmg \
    --volname "Dyktando" \
    --window-size 540 360 \
    --icon-size 96 \
    --icon "Dyktando.app" 140 180 \
    --app-drop-link 400 180 \
    "$(basename "$DMG_PATH")" \
    "$APP_PATH" || true
else
  echo "create-dmg not installed; falling back to hdiutil (no fancy layout)."
  echo "Install via: brew install create-dmg"
  STAGING="$OUT_DIR/dmg-staging"
  rm -rf "$STAGING"
  mkdir -p "$STAGING"
  cp -R "$APP_PATH" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create \
    -volname "Dyktando" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
  rm -rf "$STAGING"
fi

if [ -f "$DMG_PATH" ]; then
  echo "✓ DMG created: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
else
  echo "Error: DMG was not produced." >&2
  exit 1
fi
