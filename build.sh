#!/bin/bash
# Builds the Release app into build/release. With a Developer ID set up this
# is the signed, notarized release from Scripts/release.sh. Without one it
# builds the same app ad hoc signed and skips notarization.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"

identity="${VRAI_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p' | head -n 1)"
fi
team="${VRAI_TEAM_ID:-}"
if [[ -z "$team" && "$identity" =~ \(([A-Z0-9]{10})\)$ ]]; then
  team="${BASH_REMATCH[1]}"
fi

missing=()
[[ -n "$identity" ]] || missing+=("a Developer ID Application certificate")
[[ -n "$team" ]] || missing+=("VRAI_TEAM_ID")
for name in VRAI_NOTARY_PROFILE VRAI_FEED_URL VRAI_PUBLIC_ED_KEY VRAI_DOWNLOAD_URL_PREFIX; do
  [[ -n "${!name:-}" ]] || missing+=("$name")
done

if (( ${#missing[@]} == 0 )); then
  echo "==> Signing as $identity"
  VRAI_SIGN_IDENTITY="$identity" VRAI_TEAM_ID="$team" exec "$root/Scripts/release.sh" "$@"
fi

list="$(printf ', %s' "${missing[@]}")"
echo "==> No Apple Developer setup (missing ${list:2}), so building ad hoc without notarization"
exec "$root/Scripts/release.sh" --adhoc "$@"
