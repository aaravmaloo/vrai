#!/bin/bash
set -euo pipefail

scripts="$(cd "$(dirname "$0")" && pwd)"
build_large=1
fresh=""
keep=""
names=()
for arg in "$@"; do
  case "$arg" in
    --no-large) build_large=0 ;;
    --keep) keep=1 ;;
    --fresh) fresh="--fresh" ;;
    large) build_large=2 ;;
    *) names+=("$arg") ;;
  esac
done
if [ -z "$keep" ] && [ "${#names[@]}" -eq 0 ] && [ "$build_large" != 2 ]; then fresh="--fresh"; fi

source "$scripts/sandbox-env.sh" $fresh

if [ "${#names[@]}" -gt 0 ] && [ "$build_large" = 1 ]; then build_large=0; fi
if [ "$build_large" != 2 ] || [ "${#names[@]}" -gt 0 ]; then
  node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON "$scripts/fixtures/build.mjs" "${names[@]+"${names[@]}"}"
fi
if [ "$build_large" != 0 ]; then
  node "$scripts/fixtures/large.mjs"
fi

status=0
for repo in "$VRAI_SANDBOX"/fixtures/*/vrai "$VRAI_SANDBOX"/fixtures/empty/pocket-notes "$VRAI_SANDBOX"/fixtures/edge/edge "$VRAI_SANDBOX"/fixtures/large/monorepo "$VRAI_SANDBOX"/fixtures/welcome/swift-collections "$VRAI_SANDBOX"/fixtures/welcome/dotfiles; do
  [ -d "$repo" ] || continue
  if git -C "$repo" status --porcelain=v2 --branch >/dev/null 2>"$VRAI_SANDBOX/status.err"; then
    echo "git status ok  ${repo#$VRAI_SANDBOX/}"
  else
    echo "git status FAILED  ${repo#$VRAI_SANDBOX/}" >&2
    cat "$VRAI_SANDBOX/status.err" >&2
    status=1
  fi
done
rm -f "$VRAI_SANDBOX/status.err"
echo "sandbox: $VRAI_SANDBOX"
exit $status
