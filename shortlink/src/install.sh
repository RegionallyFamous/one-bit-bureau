#!/bin/bash

set -Eeuo pipefail

readonly PRODUCT_NAME="One-Bit Bureau"
readonly PLUGIN_ID="io.github.regionallyfamous.one-bit-bureau"
readonly REPO_URL="https://github.com/RegionallyFamous/one-bit-bureau.git"
readonly PLUGIN_TARGET="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
readonly STATE_FILE="$HOME/.local/state/omarchy/plugins/$PLUGIN_ID/install-state.json"

fail() {
  echo "one-bit-bureau install: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: bash <(curl -fsSL https://bureau.regionallyfamous.com/install) [--yes]

Installs One-Bit Bureau through Omarchy's validated Git plugin flow, then runs
the matching setup from that checkout. The default flow asks before activating
unsandboxed plugin code. Pass --yes only after reviewing the source.

Source: https://github.com/RegionallyFamous/one-bit-bureau
EOF
}

if (( $# > 0 )) && [[ $1 == "-h" || $1 == "--help" ]]; then
  usage
  exit 0
fi

(( EUID != 0 )) || fail "run this as your normal Omarchy user, not root"
command -v omarchy >/dev/null || fail "Omarchy is required; install it first from https://omarchy.org"

if [[ -e $STATE_FILE && ! -L $STATE_FILE ]]; then
  echo "$PRODUCT_NAME is already installed. Run: one-bit-bureau update"
  exit 0
fi

if [[ -e $PLUGIN_TARGET || -L $PLUGIN_TARGET ]]; then
  [[ -d $PLUGIN_TARGET/.git && ! -L $PLUGIN_TARGET ]] || fail "an unrecognized plugin path already exists at $PLUGIN_TARGET"
  [[ -f $PLUGIN_TARGET/setup && ! -L $PLUGIN_TARGET/setup ]] || fail "the existing plugin checkout has no safe setup script"
else
  echo "Fetching $PRODUCT_NAME through Omarchy's validated Git plugin flow..."
  omarchy plugin add "$REPO_URL" --yes
fi

[[ -f $PLUGIN_TARGET/setup && ! -L $PLUGIN_TARGET/setup ]] || fail "Omarchy did not install a safe setup script"
bash "$PLUGIN_TARGET/setup" --adopt-plugin "$@"
