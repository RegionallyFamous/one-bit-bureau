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
Usage: bash <(curl -fsSL https://bureau.regionallyfamous.com/install)

Installs One-Bit Bureau through Omarchy's validated Git plugin flow, then runs
the matching setup from that checkout. Running this bootstrap is consent to
activate the unsandboxed plugin code fetched from the canonical repository.

Source: https://github.com/RegionallyFamous/one-bit-bureau
EOF
}

while (( $# > 0 )); do
  case "$1" in
  --yes | -y)
    # Accepted for compatibility with the original bootstrap. The quick-install
    # command itself is now the explicit activation consent.
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    fail "unknown option: $1"
    ;;
  esac
done

(( EUID != 0 )) || fail "run this as your normal Omarchy user, not root"
command -v omarchy >/dev/null || fail "Omarchy is required; install it first from https://omarchy.org"

if [[ -e $STATE_FILE && ! -L $STATE_FILE ]]; then
  echo "$PRODUCT_NAME is already installed. Run: one-bit-bureau update"
  exit 0
fi

if [[ -e $PLUGIN_TARGET || -L $PLUGIN_TARGET ]]; then
  [[ -d $PLUGIN_TARGET/.git && ! -L $PLUGIN_TARGET ]] || fail "an unrecognized plugin path already exists at $PLUGIN_TARGET"
  [[ -f $PLUGIN_TARGET/setup && ! -L $PLUGIN_TARGET/setup ]] || fail "the existing plugin checkout has no safe setup script"
  command -v git >/dev/null || fail "Git is required to recover the existing plugin checkout"
  command -v jq >/dev/null || fail "jq is required to recover the existing plugin checkout"
  command -v omarchy-shell >/dev/null || fail "omarchy-shell is required to recover the existing plugin checkout"
  [[ $(git -C "$PLUGIN_TARGET" config --get remote.origin.url 2>/dev/null || true) == "$REPO_URL" ]] ||
    fail "the existing plugin checkout does not use the canonical repository"
  [[ -z $(git -C "$PLUGIN_TARGET" status --porcelain) ]] ||
    fail "the existing plugin checkout has local changes; review them before retrying installation"

  echo "Recovering the validated plugin checkout left by the earlier installation attempt..."
  omarchy-shell shell rescanPlugins >/dev/null
  plugin_state=""
  disable_requested=0
  for (( attempt = 0; attempt < 100; attempt++ )); do
    plugin_list=$(omarchy plugin list --json) || fail "could not inspect installed plugins during recovery"
    jq -e 'type == "array"' <<<"$plugin_list" >/dev/null || fail "Omarchy returned an invalid plugin list during recovery"
    plugin_state=$(jq -r --arg id "$PLUGIN_ID" '
      map(select(.id == $id))[0] // null |
      if . == null then ""
      elif .enabled == true then "true"
      elif .enabled == false then "false"
      else "invalid"
      end
    ' <<<"$plugin_list")
    case "$plugin_state" in
    false)
      break
      ;;
    true)
      if (( ! disable_requested )); then
        omarchy plugin disable "$PLUGIN_ID"
        disable_requested=1
      fi
      ;;
    "")
      ;;
    *)
      fail "Omarchy returned an invalid enabled state for the existing plugin"
      ;;
    esac
    sleep 0.1
  done
  [[ $plugin_state == "false" ]] || fail "Omarchy could not recover the existing plugin as installed and disabled"
  omarchy plugin update "$PLUGIN_ID" --yes
  omarchy-shell shell rescanPlugins >/dev/null
else
  echo "Fetching $PRODUCT_NAME through Omarchy's validated Git plugin flow..."
  omarchy plugin add "$REPO_URL" --yes
fi

[[ -f $PLUGIN_TARGET/setup && ! -L $PLUGIN_TARGET/setup ]] || fail "Omarchy did not install a safe setup script"
echo "Omarchy leaves new plugins disabled by design; continuing now with the matching theme, fonts, branding, and activation..."
bash "$PLUGIN_TARGET/setup" --adopt-plugin --yes
