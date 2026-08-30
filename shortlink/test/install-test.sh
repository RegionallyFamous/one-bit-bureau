#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT

MOCK_BIN="$WORK/bin"
TEST_HOME="$WORK/home"
MOCK_LOG="$WORK/calls.log"
PLUGIN_ID="io.github.regionallyfamous.one-bit-bureau"
PLUGIN_TARGET="$TEST_HOME/.config/omarchy/plugins/$PLUGIN_ID"
STATE_FILE="$TEST_HOME/.local/state/omarchy/plugins/$PLUGIN_ID/install-state.json"
mkdir -p "$MOCK_BIN" "$TEST_HOME"

cat >"$MOCK_BIN/omarchy" <<'MOCK'
#!/bin/bash
set -euo pipefail
printf 'omarchy:%s\n' "$*" >>"$MOCK_LOG"
if [[ $* == "plugin add https://github.com/RegionallyFamous/one-bit-bureau.git --yes" ]]; then
  plugin_target="$HOME/.config/omarchy/plugins/io.github.regionallyfamous.one-bit-bureau"
  mkdir -p "$plugin_target/.git"
  cat >"$plugin_target/setup" <<'SETUP'
#!/bin/bash
set -euo pipefail
printf 'setup:%s\n' "$*" >>"$MOCK_LOG"
SETUP
  chmod +x "$plugin_target/setup"
fi
MOCK
chmod +x "$MOCK_BIN/omarchy"

export MOCK_LOG
HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" bash "$ROOT/src/install.sh" --yes
[[ $(<"$MOCK_LOG") == $'omarchy:plugin add https://github.com/RegionallyFamous/one-bit-bureau.git --yes\nsetup:--adopt-plugin --yes' ]]

: >"$MOCK_LOG"
HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" bash "$ROOT/src/install.sh"
[[ $(<"$MOCK_LOG") == "setup:--adopt-plugin" ]]

mkdir -p "$(dirname -- "$STATE_FILE")"
printf '{}\n' >"$STATE_FILE"
: >"$MOCK_LOG"
already_installed=$(HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" bash "$ROOT/src/install.sh")
[[ $already_installed == *"already installed"* ]]
[[ ! -s $MOCK_LOG ]]

help=$(bash "$ROOT/src/install.sh" --help)
[[ $help == *"bureau.regionallyfamous.com/install"* ]]
[[ $help == *"validated Git plugin flow"* ]]

if HOME="$WORK/no-omarchy" PATH="$WORK/empty-bin" /bin/bash "$ROOT/src/install.sh" >"$WORK/missing.out" 2>&1; then
  echo "installer accepted a host without Omarchy" >&2
  exit 1
fi
[[ $(<"$WORK/missing.out") == *"Omarchy is required"* ]]

bash -n "$ROOT/src/install.sh"
echo "One-Bit Bureau short installer tests passed."
