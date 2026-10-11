#!/bin/bash

_vrai_tmp="${TMPDIR:-/tmp}"
_vrai_tmp="${_vrai_tmp%/}"
export VRAI_SANDBOX="${VRAI_SANDBOX:-$_vrai_tmp/vrai-sandbox}"
export VRAI_FIXTURE_NOW="${VRAI_FIXTURE_NOW:-1791720000}"
export VRAI_AUTH_PORT="${VRAI_AUTH_PORT:-47801}"

case "$VRAI_SANDBOX" in
  "$_vrai_tmp"/vrai-sandbox*|/tmp/vrai-sandbox*|/private/tmp/vrai-sandbox*|/private/var/folders/*/vrai-sandbox*|/var/folders/*/vrai-sandbox*) ;;
  *)
    echo "sandbox-env: refusing to use $VRAI_SANDBOX; it must be a vrai-sandbox folder in a temporary directory" >&2
    return 1 2>/dev/null || exit 1
    ;;
esac

if [ "${1:-}" = "--fresh" ] && [ -d "$VRAI_SANDBOX" ]; then
  chmod -R u+w "$VRAI_SANDBOX" 2>/dev/null
  rm -rf "$VRAI_SANDBOX"
fi

mkdir -p "$VRAI_SANDBOX/home/.config" "$VRAI_SANDBOX/home/.ssh" "$VRAI_SANDBOX/fixtures"
chmod 700 "$VRAI_SANDBOX/home/.ssh"
[ -f "$VRAI_SANDBOX/gitconfig" ] || : > "$VRAI_SANDBOX/gitconfig"

export HOME="$VRAI_SANDBOX/home"
export XDG_CONFIG_HOME="$VRAI_SANDBOX/home/.config"
export GIT_CONFIG_GLOBAL="$VRAI_SANDBOX/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/usr/bin/false
export SSH_ASKPASS=/usr/bin/false
export GIT_SSH_COMMAND="ssh -o BatchMode=yes"
unset SSH_AUTH_SOCK
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CEILING_DIRECTORIES
export GIT_CEILING_DIRECTORIES="$VRAI_SANDBOX"
unset _vrai_tmp
