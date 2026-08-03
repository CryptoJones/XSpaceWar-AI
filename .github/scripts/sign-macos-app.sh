#!/usr/bin/env bash
set -euo pipefail

APP="${1:?usage: sign-macos-app.sh /path/to/Application.app}"
: "${MACOS_SIGN_IDENTITY:?MACOS_SIGN_IDENTITY was not imported}"
: "${MACOS_KEYCHAIN_PATH:?MACOS_KEYCHAIN_PATH was not imported}"
[[ -d "$APP" ]] || { echo "App bundle not found: $APP" >&2; exit 1; }

codesign --force --deep --options runtime --timestamp \
  --keychain "$MACOS_KEYCHAIN_PATH" --sign "$MACOS_SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# Assert the signature actually carries the expected identity. codesign --verify
# only proves the bundle is internally consistent; it would happily pass a build
# signed by some other team, so check the authority and team id explicitly.
EXPECTED_AUTHORITY="Developer ID Application: Aaron Clark (J6P99Q4479)"
EXPECTED_TEAM_ID="J6P99Q4479"

SIGNING_DETAILS="$(codesign -dvvv "$APP" 2>&1)"
grep -Fq "Authority=$EXPECTED_AUTHORITY" <<< "$SIGNING_DETAILS"
grep -Fq "TeamIdentifier=$EXPECTED_TEAM_ID" <<< "$SIGNING_DETAILS"
echo "Verified Developer ID signature for $(basename "$APP")."
