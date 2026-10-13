#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export GIT_TERMINAL_PROMPT=0
out="$root/build/release"
packages="$root/build/SourcePackages"
mode=developer-id

usage() {
  cat <<'EOF'
Usage: Scripts/release.sh [--adhoc]

Archives the Release build, signs it inside-out with the hardened runtime,
notarizes and staples the app, builds a read-only DMG with an Applications
link, signs, notarizes and staples the DMG, and writes an EdDSA-signed Sparkle
appcast. Everything goes to build/release.

  --adhoc   Same pipeline with ad hoc signing; skips notarization and
            stapling. Needs no Apple Developer account. Writes the appcast
            only when VRAI_FEED_URL is set.

Optional environment:
  VRAI_VERSION              Version to stamp, such as 1.5.0 or 1.5.0-beta
                            (default: MARKETING_VERSION in project.yml)
  VRAI_PRIVATE_ED_KEY       Sparkle private EdDSA key (default: read from
                            the keychain by generate_appcast)

Environment for a Developer ID release:
  VRAI_SIGN_IDENTITY        Developer ID Application certificate name
  VRAI_TEAM_ID              Apple Developer team id (10 characters)
  VRAI_NOTARY_PROFILE       notarytool keychain profile name

Environment for updates (always for Developer ID, optional with --adhoc):
  VRAI_FEED_URL             https URL of appcast.xml
  VRAI_PUBLIC_ED_KEY        Sparkle public EdDSA key (base64)
  VRAI_DOWNLOAD_URL_PREFIX  https URL of the folder that hosts the DMG
EOF
}

for arg in "$@"; do
  case "$arg" in
    --adhoc) mode=adhoc ;;
    -h|--help) usage; exit 0 ;;
    *) echo "release.sh: unknown option $arg" >&2; usage >&2; exit 64 ;;
  esac
done

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'release.sh: %s\n' "$1" >&2; exit 1; }

describe() {
  case "$1" in
    VRAI_SIGN_IDENTITY) echo 'Developer ID Application certificate, for example "Developer ID Application: Aarav Maloo (TEAMID1234)"' ;;
    VRAI_TEAM_ID) echo "Apple Developer team id, 10 characters" ;;
    VRAI_NOTARY_PROFILE) echo "notarytool keychain profile saved with xcrun notarytool store-credentials" ;;
    VRAI_FEED_URL) echo "https URL where appcast.xml will be served" ;;
    VRAI_PUBLIC_ED_KEY) echo "Sparkle public EdDSA key printed by generate_keys (base64, 32 bytes)" ;;
    VRAI_DOWNLOAD_URL_PREFIX) echo "https URL of the folder that will host the DMG, ending in /" ;;
  esac
}

required=()
[[ "$mode" != developer-id ]] || required+=(VRAI_SIGN_IDENTITY VRAI_TEAM_ID VRAI_NOTARY_PROFILE)
with_updates=""
if [[ "$mode" == developer-id || -n "${VRAI_FEED_URL:-}" ]]; then
  with_updates=1
  required+=(VRAI_FEED_URL VRAI_PUBLIC_ED_KEY VRAI_DOWNLOAD_URL_PREFIX)
fi

missing=()
for name in ${required[@]+"${required[@]}"}; do
  [[ -n "${!name:-}" ]] || missing+=("$name")
done
if (( ${#missing[@]} > 0 )); then
  {
    echo "release.sh: this release needs these environment variables, and they are not set:"
    for name in "${missing[@]}"; do printf '  %-26s %s\n' "$name" "$(describe "$name")"; done
    if [[ "$mode" == developer-id ]]; then
      echo "Set them and run again, or run Scripts/release.sh --adhoc to test the pipeline without signing."
    else
      echo "Set them and run again, or unset VRAI_FEED_URL to build without updates."
    fi
  } >&2
  exit 1
fi

if [[ -n "$with_updates" ]]; then
  [[ "$VRAI_FEED_URL" == https://?* ]] || fail "VRAI_FEED_URL must be an https URL."
  [[ "$VRAI_DOWNLOAD_URL_PREFIX" == https://?* ]] || fail "VRAI_DOWNLOAD_URL_PREFIX must be an https URL."
  [[ "$(printf '%s' "$VRAI_PUBLIC_ED_KEY" | base64 -D 2>/dev/null | wc -c | tr -d ' ')" == 32 ]] || fail "VRAI_PUBLIC_ED_KEY must be the base64 public key from generate_keys."
  feed="$VRAI_FEED_URL"
  key="$VRAI_PUBLIC_ED_KEY"
else
  feed=""
  key=""
fi

if [[ "$mode" == developer-id ]]; then
  git -C "$root" diff --quiet HEAD -- || fail "Commit or stash your changes first; the build number comes from the commit count."
  identity="$VRAI_SIGN_IDENTITY"
  timestamp=(--timestamp)
  team="$VRAI_TEAM_ID"
else
  identity="-"
  timestamp=(--timestamp=none)
  team=""
fi

for tool in xcodegen xcodebuild git hdiutil codesign ditto python3; do
  command -v "$tool" >/dev/null || fail "$tool was not found."
done

build="$(git -C "$root" rev-list --count HEAD)"
archive="$out/Vrai.xcarchive"
export_dir="$out/export"
app="$export_dir/Vrai.app"

step "Preparing build/release (build $build, $mode)"
for _ in 1 2 3; do rm -rf "$out" 2>/dev/null && break; sleep 1; done
[[ ! -e "$out" ]] || fail "Could not clear build/release. Close any Finder window showing it and try again."
mkdir -p "$out" "$packages"
(cd "$root" && xcodegen generate --quiet)

step "Archiving the Release build"
archive_signing=(CODE_SIGN_IDENTITY="$identity")
if [[ "$mode" == developer-id ]]; then
  archive_signing+=(DEVELOPMENT_TEAM="$team" OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime")
fi
versioning=(CURRENT_PROJECT_VERSION="$build")
[[ -z "${VRAI_VERSION:-}" ]] || versioning+=(MARKETING_VERSION="$VRAI_VERSION")
xcodebuild archive \
  -project "$root/Vrai.xcodeproj" -scheme Vrai -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive" \
  -derivedDataPath "$out/DerivedData" \
  -clonedSourcePackagesDirPath "$packages" \
  -scmProvider system -packageAuthorizationProvider netrc \
  "${versioning[@]}" \
  VRAI_FEED_URL="$feed" VRAI_PUBLIC_ED_KEY="$key" \
  "${archive_signing[@]}" \
  -quiet
[[ -d "$archive/Products/Applications/Vrai.app" ]] || fail "The archive has no Vrai.app."

step "Exporting the app"
if [[ "$mode" == developer-id ]]; then
  options="$out/ExportOptions.plist"
  /usr/bin/plutil -create xml1 "$options"
  /usr/bin/plutil -insert method -string developer-id "$options"
  /usr/bin/plutil -insert destination -string export "$options"
  /usr/bin/plutil -insert signingStyle -string manual "$options"
  /usr/bin/plutil -insert signingCertificate -string "$identity" "$options"
  /usr/bin/plutil -insert teamID -string "$team" "$options"
  xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export_dir" -exportOptionsPlist "$options" -quiet
else
  mkdir -p "$export_dir"
  ditto "$archive/Products/Applications/Vrai.app" "$app"
fi
[[ -d "$app" ]] || fail "The export has no Vrai.app."

info="$app/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")"
bundle_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")"
[[ "$bundle_build" == "$build" ]] || fail "The app says build $bundle_build, expected $build."
[[ -z "${VRAI_VERSION:-}" || "$version" == "$VRAI_VERSION" ]] || fail "The app says version $version, expected $VRAI_VERSION."
echo "Vrai $version ($bundle_build)"

sign() {
  echo "  signing ${1#"$export_dir"/}"
  codesign --force --sign "$identity" --options runtime "${timestamp[@]}" "${@:2}" "$1"
}

step "Signing inside-out with the hardened runtime"
sparkle="$app/Contents/Frameworks/Sparkle.framework"
if [[ -d "$sparkle" ]]; then
  current="$sparkle/Versions/Current"
  [[ -d "$current/XPCServices/Installer.xpc" ]] && sign "$current/XPCServices/Installer.xpc"
  [[ -d "$current/XPCServices/Downloader.xpc" ]] && sign "$current/XPCServices/Downloader.xpc" --preserve-metadata=entitlements
  [[ -f "$current/Autoupdate" ]] && sign "$current/Autoupdate"
  [[ -d "$current/Updater.app" ]] && sign "$current/Updater.app"
  sign "$sparkle"
fi
while IFS= read -r -d '' nested; do
  sign "$nested"
done < <(find "$app/Contents/Frameworks" -mindepth 1 -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) ! -name Sparkle.framework -print0 2>/dev/null)
sign "$app/Contents/MacOS/vrai-askpass" --identifier com.aaravmaloo.vrai.askpass
sign "$app/Contents/MacOS/vrai-editor" --identifier com.aaravmaloo.vrai.editor
entitlements="$root/App/Vrai.entitlements"
if [[ "$mode" == adhoc ]]; then
  entitlements="$out/adhoc.entitlements"
  cp "$root/App/Vrai.entitlements" "$entitlements"
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$entitlements"
fi
sign "$app" --identifier com.aaravmaloo.vrai --entitlements "$entitlements"
codesign --verify --deep --strict --verbose=2 "$app"

notarize() {
  local file="$1" name="$2" result="$out/notary-$2.json"
  echo "  submitting $name"
  xcrun notarytool submit "$file" --keychain-profile "$VRAI_NOTARY_PROFILE" --wait --output-format json > "$result"
  local status
  status="$(/usr/bin/plutil -extract status raw -o - "$result" 2>/dev/null || echo unknown)"
  if [[ "$status" != Accepted ]]; then
    local id
    id="$(/usr/bin/plutil -extract id raw -o - "$result" 2>/dev/null || echo "")"
    fail "Notarization of $name ended with status $status. Read why with: xcrun notarytool log $id --keychain-profile \"$VRAI_NOTARY_PROFILE\""
  fi
}

if [[ "$mode" == developer-id ]]; then
  step "Notarizing and stapling the app"
  ditto -c -k --keepParent "$app" "$out/Vrai.zip"
  notarize "$out/Vrai.zip" app
  xcrun stapler staple "$app"
  rm -f "$out/Vrai.zip"
else
  step "Skipping notarization and stapling of the app (ad hoc)"
fi

step "Building the DMG"
dmg="$out/Vrai-$version.dmg"
tools="$root/build/tools/dmgbuild"
if [[ ! -x "$tools/bin/dmgbuild" ]]; then
  echo "  installing dmgbuild into build/tools"
  python3 -m venv "$tools"
  "$tools/bin/pip" install --quiet --disable-pip-version-check "dmgbuild==1.6.7"
fi
"$tools/bin/dmgbuild" -s "$root/Scripts/dmg/settings.py" -D app="$app" -D background="$root/Scripts/dmg/background.png" "Vrai $version" "$dmg" > /dev/null
codesign --force --sign "$identity" "${timestamp[@]}" "$dmg"
codesign --verify --verbose=2 "$dmg"

if [[ "$mode" == developer-id ]]; then
  step "Notarizing and stapling the DMG"
  notarize "$dmg" dmg
  xcrun stapler staple "$dmg"
fi

if [[ -n "$with_updates" ]]; then
  step "Writing the EdDSA-signed appcast"
  generate_appcast="$packages/artifacts/sparkle/Sparkle/bin/generate_appcast"
  [[ -x "$generate_appcast" ]] || fail "generate_appcast was not found at $generate_appcast."
  updates="$out/updates"
  mkdir -p "$updates"
  cp "$dmg" "$updates/"
  appcast=(--download-url-prefix "$VRAI_DOWNLOAD_URL_PREFIX" -o "$out/appcast.xml" "$updates")
  if [[ -n "${VRAI_PRIVATE_ED_KEY:-}" ]]; then
    printf '%s' "$VRAI_PRIVATE_ED_KEY" | "$generate_appcast" --ed-key-file - "${appcast[@]}"
  else
    "$generate_appcast" "${appcast[@]}"
  fi
  rm -rf "$updates"
else
  step "Skipping the appcast (no VRAI_FEED_URL)"
fi

rm -rf "$out/DerivedData"

step "Done"
echo "App: $app"
echo "DMG: $dmg"
[[ -f "$out/appcast.xml" ]] && echo "Appcast: $out/appcast.xml"
exit 0
