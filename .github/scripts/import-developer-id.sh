#!/usr/bin/env bash
set -euo pipefail

: "${RUNNER_TEMP:?RUNNER_TEMP must be set by GitHub Actions}"
: "${GITHUB_ENV:?GITHUB_ENV must be set by GitHub Actions}"
: "${MACOS_CERTIFICATE_P12:?MACOS_CERTIFICATE_P12 secret is required}"
: "${MACOS_CERTIFICATE_PASSWORD:?MACOS_CERTIFICATE_PASSWORD secret is required}"

KEYCHAIN_PATH="$RUNNER_TEMP/developer-id.keychain-db"
CERTIFICATE_PATH="$RUNNER_TEMP/developer-id.p12"
KEYCHAIN_PASSWORD="$(uuidgen)-$(uuidgen)"

trap 'rm -f "$CERTIFICATE_PATH"' EXIT
printf '%s' "$MACOS_CERTIFICATE_P12" \
  | openssl base64 -d -A -out "$CERTIFICATE_PATH"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERTIFICATE_PATH" -k "$KEYCHAIN_PATH" \
  -P "$MACOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12
security set-key-partition-list -S apple-tool:,apple: -s \
  -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH"
security default-keychain -d user -s "$KEYCHAIN_PATH"

IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" \
  | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p')"
if [[ -z "$IDENTITY" || "$IDENTITY" != *"(GPKDR6QL9Q)" ]]; then
  echo "Expected Developer ID Application identity was not imported" >&2
  exit 1
fi

echo "MACOS_SIGN_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"
echo "MACOS_KEYCHAIN_PATH=$KEYCHAIN_PATH" >> "$GITHUB_ENV"
echo "Imported the expected Developer ID Application identity."
