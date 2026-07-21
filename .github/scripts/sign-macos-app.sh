#!/usr/bin/env bash
set -euo pipefail

APP="${1:?usage: sign-macos-app.sh /path/to/Application.app}"
: "${MACOS_SIGN_IDENTITY:?MACOS_SIGN_IDENTITY was not imported}"
: "${MACOS_KEYCHAIN_PATH:?MACOS_KEYCHAIN_PATH was not imported}"
[[ -d "$APP" ]] || { echo "App bundle not found: $APP" >&2; exit 1; }

codesign --force --deep --options runtime --timestamp \
  --keychain "$MACOS_KEYCHAIN_PATH" --sign "$MACOS_SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

SIGNING_DETAILS="$(codesign -dvvv "$APP" 2>&1)"
grep -Fq "Authority=Developer ID Application: Patrick Hannah (GPKDR6QL9Q)" \
  <<< "$SIGNING_DETAILS"
grep -Fq "TeamIdentifier=GPKDR6QL9Q" <<< "$SIGNING_DETAILS"
echo "Verified Developer ID signature for $(basename "$APP")."
