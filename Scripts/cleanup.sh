#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
all=""
dry=""
yes=""

usage() {
  cat <<'EOF'
Usage: Scripts/cleanup.sh [--all] [--dry-run] [--yes]

Deletes build products that the scripts and Xcode recreate on their own:
debug builds, test results, screenshots, package caches, and the Xcode
DerivedData folders of this checkout and of worktrees made inside it. The
latest release in build/release (DMG, appcast, and the archive with its
dSYMs) is kept.

Nothing tracked by git is touched, and nothing a running process was
launched from. It lists what it would delete with sizes and asks first.

  --all      Also delete build/release, Xcode archives of Vrai, and the test
             fixtures in $TMPDIR/vrai-sandbox (Scripts/make-fixtures.sh
             rebuilds them).
  --dry-run  Only list what would be deleted.
  --yes      Delete without asking.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --all) all=1 ;;
    --dry-run|-n) dry=1 ;;
    --yes|-y) yes=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "cleanup.sh: unknown option $arg" >&2; usage >&2; exit 64 ;;
  esac
done

targets=()
skipped=()
running="$(ps -axo command= 2>/dev/null || true)"

consider() {
  local path="$1"
  [[ -e "$path" || -L "$path" ]] || return 0
  case "$path" in
    "$root"/*)
      local rel="${path#"$root"/}"
      if [[ -n "$(git -C "$root" ls-files -- "$rel" 2>/dev/null | head -n 1)" ]]; then
        skipped+=("$rel (tracked by git)")
        return 0
      fi
      ;;
  esac
  if [[ ! -L "$path" ]] && grep -qiF -- "$path/" <<<"$running"; then
    skipped+=("${path#"$root"/} (in use by a running process)")
    return 0
  fi
  targets+=("$path")
}

# Inside the checkout.
if [[ -n "$all" ]]; then
  consider "$root/build"
else
  for path in "$root"/build/*; do
    [[ "$path" == "$root/build/release" ]] && continue
    consider "$path"
  done
  for name in export DerivedData updates Vrai.zip ExportOptions.plist adhoc.entitlements; do
    consider "$root/build/release/$name"
  done
  for path in "$root"/build/release/notary-*.json; do consider "$path"; done
fi
consider "$root/Packages/VraiKit/.build"
consider "$root/Packages/VraiKit/.swiftpm"

# Xcode's DerivedData for this checkout and any worktree inside it, including
# worktrees that have since been removed. macOS paths ignore case, and the
# checkout may have been reached as ~/desktop rather than ~/Desktop.
shopt -s nocasematch
derived="$HOME/Library/Developer/Xcode/DerivedData"
for path in "$derived"/*; do
  [[ -f "$path/info.plist" ]] || continue
  workspace="$(/usr/bin/plutil -extract WorkspacePath raw -o - "$path/info.plist" 2>/dev/null || true)"
  if [[ "$workspace" == "$root"/* ]]; then consider "$path"; fi
done
shopt -u nocasematch

if [[ -n "$all" ]]; then
  archives="$HOME/Library/Developer/Xcode/Archives"
  for path in "$archives"/*/*.xcarchive; do
    [[ -f "$path/Info.plist" ]] || continue
    name="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$path/Info.plist" 2>/dev/null || true)"
    [[ "$name" == Vrai ]] && consider "$path"
  done
  tmp="${TMPDIR:-/tmp}"
  consider "${tmp%/}/vrai-sandbox"
fi

human() {
  awk -v k="$1" 'BEGIN { split("K M G T", u, " "); i = 1; while (k >= 1024 && i < 4) { k /= 1024; i++ } printf (i == 1 ? "%d%s" : "%.1f%s"), k, u[i] }'
}

label() {
  case "$1" in
    "$root"/*) echo "${1#"$root"/}" ;;
    "$HOME"/*) echo "~/${1#"$HOME"/}" ;;
    *) echo "$1" ;;
  esac
}

for item in ${skipped[@]+"${skipped[@]}"}; do echo "keeping $item"; done

if (( ${#targets[@]} == 0 )); then
  echo "Nothing to clean."
  exit 0
fi

total=0
for path in "${targets[@]}"; do
  kb="$(du -sk "$path" 2>/dev/null | awk '{ print $1 }')"
  kb="${kb:-0}"
  total=$((total + kb))
  printf '%8s  %s\n' "$(human "$kb")" "$(label "$path")"
done
printf '%8s  total\n' "$(human "$total")"

if [[ -n "$dry" ]]; then
  echo "Dry run, nothing deleted."
  exit 0
fi

if [[ -z "$yes" ]]; then
  if [[ ! -t 0 ]]; then
    echo "cleanup.sh: not a terminal, so pass --yes to delete." >&2
    exit 1
  fi
  read -r -p "Delete these? [y/N] " answer
  [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]] || { echo "Nothing deleted."; exit 0; }
fi

if pgrep -xq Xcode; then
  echo "Xcode is open, so it may rebuild some DerivedData right away."
fi

for path in "${targets[@]}"; do
  if [[ -L "$path" ]]; then
    rm -f "$path"
  else
    chmod -R u+w "$path" 2>/dev/null || true
    rm -rf "$path"
  fi
done
echo "Freed about $(human "$total")."
