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

  --adhoc   Same pipeline with ad hoc signing; skips notarization, stapling
            and the appcast. Needs no Apple Developer account.

Environment for a Developer ID release:
  VRAI_SIGN_IDENTITY        Developer ID Application certificate name
  VRAI_TEAM_ID              Apple Developer team id (10 characters)
  VRAI_NOTARY_PROFILE       notarytool keychain profile name
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

required=(VRAI_SIGN_IDENTITY VRAI_TEAM_ID VRAI_NOTARY_PROFILE VRAI_FEED_URL VRAI_PUBLIC_ED_KEY VRAI_DOWNLOAD_URL_PREFIX)

if [[ "$mode" == developer-id ]]; then
  missing=()
  for name in "${required[@]}"; do
    [[ -n "${!name:-}" ]] || missing+=("$name")
  done
  if (( ${#missing[@]} > 0 )); then
    {
      echo "release.sh: a Developer ID release needs these environment variables, and they are not set:"
      for name in "${missing[@]}"; do printf '  %-26s %s\n' "$name" "$(describe "$name")"; done
      echo "Set them and run again, or run Scripts/release.sh --adhoc to test the pipeline without signing."
    } >&2
    exit 1
  fi
  [[ "$VRAI_FEED_URL" == https://?* ]] || fail "VRAI_FEED_URL must be an https URL."
  [[ "$VRAI_DOWNLOAD_URL_PREFIX" == https://?* ]] || fail "VRAI_DOWNLOAD_URL_PREFIX must be an https URL."
  [[ "$(printf '%s' "$VRAI_PUBLIC_ED_KEY" | base64 -D 2>/dev/null | wc -c | tr -d ' ')" == 32 ]] || fail "VRAI_PUBLIC_ED_KEY must be the base64 public key from generate_keys."
  git -C "$root" diff --quiet HEAD -- || fail "Commit or stash your changes first; the build number comes from the commit count."
  identity="$VRAI_SIGN_IDENTITY"
  timestamp=(--timestamp)
  feed="$VRAI_FEED_URL"
  key="$VRAI_PUBLIC_ED_KEY"
  team="$VRAI_TEAM_ID"
else
  identity="-"
  timestamp=(--timestamp=none)
  feed=""
  key=""
  team=""
fi

for tool in xcodegen xcodebuild git hdiutil codesign ditto; do
  command -v "$tool" >/dev/null || fail "$tool was not found."
done

build="$(git -C "$root" rev-list --count HEAD)"
archive="$out/Vrai.xcarchive"
export_dir="$out/export"
app="$export_dir/Vrai.app"

step "Preparing build/release (build $build, $mode)"
rm -rf "$out"
mkdir -p "$out" "$packages"
(cd "$root" && xcodegen generate --quiet)

step "Archiving the Release build"
archive_signing=(CODE_SIGN_IDENTITY="$identity")
if [[ "$mode" == developer-id ]]; then
  archive_signing+=(DEVELOPMENT_TEAM="$team" OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime")
fi
xcodebuild archive \
  -project "$root/Vrai.xcodeproj" -scheme Vrai -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive" \
  -derivedDataPath "$out/DerivedData" \
  -clonedSourcePackagesDirPath "$packages" \
  -scmProvider system -packageAuthorizationProvider netrc \
  CURRENT_PROJECT_VERSION="$build" \
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
sign "$app" --identifier com.aaravmaloo.vrai --entitlements "$root/App/Vrai.entitlements"
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
stage="$out/dmg"
dmg="$out/Vrai-$version.dmg"
mkdir -p "$stage"
ditto "$app" "$stage/Vrai.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Vrai $version" -srcfolder "$stage" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$dmg" -quiet
rm -rf "$stage"
codesign --force --sign "$identity" "${timestamp[@]}" "$dmg"
codesign --verify --verbose=2 "$dmg"

if [[ "$mode" == developer-id ]]; then
  step "Notarizing and stapling the DMG"
  notarize "$dmg" dmg
  xcrun stapler staple "$dmg"

  step "Writing the EdDSA-signed appcast"
  generate_appcast="$packages/artifacts/sparkle/Sparkle/bin/generate_appcast"
  [[ -x "$generate_appcast" ]] || fail "generate_appcast was not found at $generate_appcast."
  updates="$out/updates"
  mkdir -p "$updates"
  cp "$dmg" "$updates/"
  "$generate_appcast" --download-url-prefix "$VRAI_DOWNLOAD_URL_PREFIX" -o "$out/appcast.xml" "$updates"
  rm -rf "$updates"
else
  step "Skipping the appcast (ad hoc)"
fi

step "Done"
echo "App: $app"
echo "DMG: $dmg"
[[ -f "$out/appcast.xml" ]] && echo "Appcast: $out/appcast.xml"
exit 0
