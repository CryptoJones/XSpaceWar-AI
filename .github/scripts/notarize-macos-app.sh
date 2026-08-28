#!/usr/bin/env bash
set -euo pipefail

# Submits an already Developer ID signed .app to Apple's notary service,
# staples the resulting ticket into the bundle, and proves the staple took.
# Signing is a prerequisite: notarization rejects anything that is not signed
# with a Developer ID identity, hardened runtime, and a secure timestamp.

APP="${1:?usage: notarize-macos-app.sh /path/to/Application.app}"
: "${RUNNER_TEMP:?RUNNER_TEMP must be set by GitHub Actions}"
: "${MACOS_NOTARY_ISSUER_ID:?MACOS_NOTARY_ISSUER_ID secret is required}"
: "${MACOS_NOTARY_KEY_ID:?MACOS_NOTARY_KEY_ID secret is required}"
: "${MACOS_NOTARY_KEY_P8:?MACOS_NOTARY_KEY_P8 secret is required}"
[[ -d "$APP" ]] || { echo "App bundle not found: $APP" >&2; exit 1; }

KEY_PATH="$RUNNER_TEMP/notary-key.p8"
SUBMIT_ZIP="$RUNNER_TEMP/notarize-submission.zip"
trap 'rm -f "$KEY_PATH" "$SUBMIT_ZIP"' EXIT

printf '%s' "$MACOS_NOTARY_KEY_P8" | openssl base64 -d -A -out "$KEY_PATH"
chmod 0600 "$KEY_PATH"

# The notary service takes an archive, not a bundle. This zip is only the
# submission vehicle — the ticket is stapled into the .app afterwards and the
# release archive is rebuilt from the stapled bundle.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$SUBMIT_ZIP"

echo "Submitting $(basename "$APP") to the Apple notary service..."
set +e
submission="$(xcrun notarytool submit "$SUBMIT_ZIP" \
  --issuer "$MACOS_NOTARY_ISSUER_ID" \
  --key-id "$MACOS_NOTARY_KEY_ID" \
  --key "$KEY_PATH" \
  --wait --timeout 30m --output-format json)"
submit_status=$?
set -e

if [[ $submit_status -ne 0 || -z "$submission" ]]; then
  echo "notarytool submit failed (exit $submit_status): $submission" >&2
  exit 1
fi

read -r notary_status submission_id < <(
  python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("status","unknown"), d.get("id",""))' \
    <<< "$submission"
)
echo "Notary service returned status: $notary_status (submission $submission_id)"

if [[ "$notary_status" != "Accepted" ]]; then
  # The summary never says WHY a submission was rejected; the log does.
  echo "Notarization was not accepted. Fetching the notary log:" >&2
  xcrun notarytool log "$submission_id" \
    --issuer "$MACOS_NOTARY_ISSUER_ID" \
    --key-id "$MACOS_NOTARY_KEY_ID" \
    --key "$KEY_PATH" >&2 || true
  exit 1
fi

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# Gatekeeper's own verdict, as a user would get it. Informational: stapler
# validate above is the hard gate, but a "rejected" here means the ticket is
# stapled and still unacceptable, which is worth failing on.
assessment="$(spctl --assess --type exec -vvv "$APP" 2>&1 || true)"
echo "$assessment"
if grep -q "rejected" <<< "$assessment"; then
  echo "Gatekeeper rejected the notarized app." >&2
  exit 1
fi

echo "Notarized and stapled $(basename "$APP")."
