#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT

MOCK_BIN="$WORK/bin"
TEST_HOME="$WORK/home"
MOCK_LOG="$WORK/calls.log"
PLUGIN_STATE_FILE="$WORK/plugin-state"
PLUGIN_ID="io.github.regionallyfamous.one-bit-bureau"
PLUGIN_TARGET="$TEST_HOME/.config/omarchy/plugins/$PLUGIN_ID"
STATE_FILE="$TEST_HOME/.local/state/omarchy/plugins/$PLUGIN_ID/install-state.json"
mkdir -p "$MOCK_BIN" "$TEST_HOME"

cat >"$MOCK_BIN/omarchy" <<'MOCK'
#!/bin/bash
set -euo pipefail
printf 'omarchy:%s\n' "$*" >>"$MOCK_LOG"
if [[ $* == "plugin list --json" ]]; then
  printf '[{"id":"io.github.regionallyfamous.one-bit-bureau","enabled":%s}]\n' "$(<"$PLUGIN_STATE_FILE")"
elif [[ $* == "plugin disable io.github.regionallyfamous.one-bit-bureau" ]]; then
  printf 'false\n' >"$PLUGIN_STATE_FILE"
elif [[ $* == "plugin add https://github.com/RegionallyFamous/one-bit-bureau.git --yes" ]]; then
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

cat >"$MOCK_BIN/omarchy-shell" <<'MOCK'
#!/bin/bash
set -euo pipefail
printf 'omarchy-shell:%s\n' "$*" >>"$MOCK_LOG"
MOCK
chmod +x "$MOCK_BIN/omarchy-shell"

cat >"$MOCK_BIN/git" <<'MOCK'
#!/bin/bash
set -euo pipefail
if [[ $* == *"config --get remote.origin.url"* ]]; then
  printf 'https://github.com/RegionallyFamous/one-bit-bureau.git\n'
elif [[ $* == *"status --porcelain"* ]]; then
  exit 0
else
  exit 1
fi
MOCK
chmod +x "$MOCK_BIN/git"

export MOCK_LOG PLUGIN_STATE_FILE
printf 'false\n' >"$PLUGIN_STATE_FILE"
HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" bash "$ROOT/src/install.sh" --yes
[[ $(<"$MOCK_LOG") == $'omarchy:plugin add https://github.com/RegionallyFamous/one-bit-bureau.git --yes\nsetup:--adopt-plugin --yes' ]]

: >"$MOCK_LOG"
HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" bash "$ROOT/src/install.sh"
[[ $(<"$MOCK_LOG") == $'omarchy-shell:shell rescanPlugins\nomarchy:plugin list --json\nomarchy:plugin update io.github.regionallyfamous.one-bit-bureau --yes\nomarchy-shell:shell rescanPlugins\nsetup:--adopt-plugin --yes' ]]

printf 'true\n' >"$PLUGIN_STATE_FILE"
: >"$MOCK_LOG"
recovery_output=$(HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" bash "$ROOT/src/install.sh")
[[ $(<"$MOCK_LOG") == $'omarchy-shell:shell rescanPlugins\nomarchy:plugin list --json\nomarchy:plugin disable io.github.regionallyfamous.one-bit-bureau\nomarchy:plugin list --json\nomarchy:plugin update io.github.regionallyfamous.one-bit-bureau --yes\nomarchy-shell:shell rescanPlugins\nsetup:--adopt-plugin --yes' ]]
[[ $recovery_output == *"Recovering the validated plugin checkout"* ]]
[[ $recovery_output == *"continuing now with the matching theme"* ]]

if HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" bash "$ROOT/src/install.sh" --bogus >"$WORK/unknown.out" 2>&1; then
  echo "installer accepted an unknown option" >&2
  exit 1
fi
[[ $(<"$WORK/unknown.out") == *"unknown option: --bogus"* ]]

mkdir -p "$(dirname -- "$STATE_FILE")"
printf '{}\n' >"$STATE_FILE"
: >"$MOCK_LOG"
already_installed=$(HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" bash "$ROOT/src/install.sh")
[[ $already_installed == *"already installed"* ]]
[[ ! -s $MOCK_LOG ]]

help=$(bash "$ROOT/src/install.sh" --help)
[[ $help == *"bureau.regionallyfamous.com/install"* ]]
[[ $help == *"validated Git plugin flow"* ]]
[[ $help == *"Running this bootstrap is consent"* ]]

if HOME="$WORK/no-omarchy" PATH="$WORK/empty-bin" /bin/bash "$ROOT/src/install.sh" >"$WORK/missing.out" 2>&1; then
  echo "installer accepted a host without Omarchy" >&2
  exit 1
fi
[[ $(<"$WORK/missing.out") == *"Omarchy is required"* ]]

bash -n "$ROOT/src/install.sh"
echo "One-Bit Bureau short installer tests passed."
