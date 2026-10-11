#!/bin/bash
set -euo pipefail

scripts="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$scripts")"
vrai="$root"
tmp="${TMPDIR:-/tmp}"
sandbox="${VRAI_SANDBOX:-${tmp%/}/vrai-sandbox}"
out="$root/build/screens"
results="$root/build/results/flows-$(date +%Y%m%d-%H%M%S).xcresult"
only=()
for arg in "$@"; do only+=("-only-testing:VraiFlowTests/$arg"); done

mkdir -p "$out" "$(dirname "$results")"
(cd "$vrai" && xcodegen generate --quiet)
set +e
TEST_RUNNER_VRAI_SANDBOX="$sandbox" /usr/bin/lockf -k "${tmp%/}/vrai-ui-tests.lock" xcodebuild test \
  -project "$vrai/Vrai.xcodeproj" -scheme Vrai -destination 'platform=macOS' \
  -resultBundlePath "$results" "${only[@]+"${only[@]}"}" 2>&1 | grep -E "Test Case|error:|failed|passed|\*\* TEST" | sed 's/^/  /'
status=${PIPESTATUS[0]}
set -e
xcrun xcresulttool export attachments --path "$results" --output-path "$out" >/dev/null
node -e '
const fs = require("fs"), path = require("path");
const dir = process.argv[1];
const manifest = JSON.parse(fs.readFileSync(path.join(dir, "manifest.json"), "utf8"));
for (const test of manifest) for (const a of test.attachments || []) {
  const name = (a.suggestedHumanReadableName || a.exportedFileName).replace(/_\d+_[0-9A-F-]+(?=\.\w+$)/i, "");
  fs.renameSync(path.join(dir, a.exportedFileName), path.join(dir, name));
  console.log("  " + path.join(dir, name));
}
fs.rmSync(path.join(dir, "manifest.json"));
' "$out"
echo "results: $results"
exit "$status"
