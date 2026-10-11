#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/Scripts/sandbox-env.sh" >/dev/null
rm -f "$root/build/perf/budgets.txt"
cd "$root/Packages/VraiKit"
VRAI_PERF=1 swift test --filter PerformanceTests 2>&1 | grep -E "error:|failed|recorded an issue|Test run with"
cat "$root/build/perf/budgets.txt"
