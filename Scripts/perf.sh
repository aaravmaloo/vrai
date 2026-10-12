#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/Scripts/sandbox-env.sh" >/dev/null
out="$root/build/perf"
engine_only=""
tests=()
for arg in "$@"; do
  case "$arg" in
    --engine) engine_only=1 ;;
    *) tests+=("PerfFlowTests/$arg") ;;
  esac
done
[ "${#tests[@]}" -gt 0 ] || tests=(PerfFlowTests)

mkdir -p "$out" "$VRAI_SANDBOX/perf"
rm -f "$out/engine.txt" "$out/views.txt" "$out/budgets.txt" "$out/metrics.json"
[ -n "$engine_only" ] || rm -f "$VRAI_SANDBOX/perf/ui-budgets.txt"

echo "engine and view timings (swift test, debug build)"
(cd "$root/Packages/VraiKit" && VRAI_PERF=1 swift test --filter 'PerformanceTests|PerformanceViewTests' 2>&1 | grep -E "error:|failed|recorded an issue|Test run with" | sed 's/^/  /') || true

results=""
if [ -z "$engine_only" ]; then
  echo "app timings (UI tests, debug build, waits for the shared UI test lock)"
  set +e
  "$root/Scripts/screenshots.sh" "${tests[@]}" > "$out/ui.log" 2>&1
  set -e
  grep -E "Test Case|error:|\*\* TEST" "$out/ui.log" | sed 's/^/  /' || true
  results="$(sed -n 's/^results: //p' "$out/ui.log" | tail -1)"
  if [ -n "$results" ] && [ -d "$results" ]; then
    xcrun xcresulttool get test-results metrics --path "$results" > "$out/metrics.json" 2>/dev/null || true
  fi
fi

{
  echo "Vrai performance budgets ($(date '+%Y-%m-%d %H:%M'), $(sysctl -n machdep.cpu.brand_string), load $(sysctl -n vm.loadavg | tr -d '{}' | awk '{print $1}'))"
  echo
  echo "Budget | Measured | Limit | Result | Notes"
  if [ -f "$VRAI_SANDBOX/perf/ui-budgets.txt" ]; then
    [ -z "$engine_only" ] || echo "(app timings from the last UI run, $(date -r "$VRAI_SANDBOX/perf/ui-budgets.txt" '+%Y-%m-%d %H:%M'))"
    cat "$VRAI_SANDBOX/perf/ui-budgets.txt"
  else
    echo "(no app timings; run without --engine)"
  fi
  if [ -s "$out/metrics.json" ]; then
    echo
    echo "XCTest metrics"
    node -e '
const data = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const runs = Array.isArray(data) ? data : (data.testRuns || data.tests || [data]);
const seen = [];
const walk = (node, test) => {
  if (!node || typeof node !== "object") return;
  if (Array.isArray(node)) return node.forEach((item) => walk(item, test));
  const name = node.testIdentifier || node.testName || node.name || test;
  if (node.displayName && Array.isArray(node.measurements)) {
    const values = node.measurements.map(Number).filter((v) => !Number.isNaN(v));
    if (values.length) seen.push(String(name).replace(/^.*\//, "") + " | " + node.displayName + " | " + values.map((v) => v.toFixed(2)).join(", ") + " " + (node.unitOfMeasurement || node.unit || ""));
  }
  for (const value of Object.values(node)) walk(value, name);
};
walk(runs, "");
console.log(seen.join("\n") || "(none)");
' "$out/metrics.json" || echo "(could not read $out/metrics.json)"
  fi
  echo
  echo "View timings (the real views in an offscreen window, no accessibility client)"
  if [ -f "$out/views.txt" ]; then cat "$out/views.txt"; else echo "(none)"; fi
  echo
  echo "Engine timings"
  if [ -f "$out/engine.txt" ]; then cat "$out/engine.txt"; else echo "(none)"; fi
} > "$out/budgets.txt"
cat "$out/budgets.txt"
