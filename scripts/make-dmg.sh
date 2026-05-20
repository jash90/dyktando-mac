#!/usr/bin/env bash
set -euo pipefail

# Resolve to absolute paths immediately — create-dmg internally `cd`s into a
# staging dir, so relative paths from the caller break partway through.
ARCHIVE_ARG="$1"
OUT_DIR_ARG="${2:-build}"
ARCHIVE="$(cd "$(dirname "$ARCHIVE_ARG")" && pwd)/$(basename "$ARCHIVE_ARG")"
mkdir -p "$OUT_DIR_ARG"
OUT_DIR="$(cd "$OUT_DIR_ARG" && pwd)"
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
  # Force POSIX locale for create-dmg's internal AppleScript — Polish locale
  # produces "Nie można ustawić item ..." errors when Finder tries to set
  # icon positions on the mounted volume.
  if LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 create-dmg \
    --volname "Dyktando" \
    --window-size 540 360 \
    --icon-size 96 \
    --icon "Dyktando.app" 140 180 \
    --app-drop-link 400 180 \
    "$DMG_PATH" \
    "$APP_PATH"; then
    : # success
  else
    echo "create-dmg failed; falling back to hdiutil…" >&2
  fi
fi

if [ ! -f "$DMG_PATH" ]; then
  echo "Building DMG with hdiutil (no fancy layout)…"
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
