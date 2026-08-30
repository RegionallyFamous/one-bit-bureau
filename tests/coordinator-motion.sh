#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

TEST_HOME="$WORK/home"
BIN="$WORK/bin"
PLUGIN_ID="io.github.regionallyfamous.one-bit-bureau"
PLUGIN_DIR="$TEST_HOME/.config/omarchy/plugins/$PLUGIN_ID"
STATE_DIR="$TEST_HOME/.local/state/omarchy/plugins/$PLUGIN_ID"
LOG="$WORK/commands.log"

mkdir -p "$BIN" "$PLUGIN_DIR" "$STATE_DIR"
printf '{}\n' >"$PLUGIN_DIR/manifest.json"
printf '{}\n' >"$STATE_DIR/install-state.json"

cat >"$BIN/omarchy" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_LOG"
EOF

cat >"$BIN/omarchy-shell" <<'EOF'
#!/bin/bash
cat <<'JSON'
{"bar":{"layout":{"left":[{"id":"io.github.regionallyfamous.one-bit-bureau","reducedMotion":true}],"center":[],"right":[]}}}
JSON
EOF

chmod +x "$BIN/omarchy" "$BIN/omarchy-shell"

HOME="$TEST_HOME" TEST_LOG="$LOG" PATH="$BIN:$PATH" bash "$ROOT/one-bit-bureau" motion reduce
grep -Fxq 'bar set io.github.regionallyfamous.one-bit-bureau reducedMotion true --json' "$LOG"

HOME="$TEST_HOME" TEST_LOG="$LOG" PATH="$BIN:$PATH" bash "$ROOT/one-bit-bureau" motion full
grep -Fxq 'bar set io.github.regionallyfamous.one-bit-bureau reducedMotion false --json' "$LOG"

[[ $(HOME="$TEST_HOME" TEST_LOG="$LOG" PATH="$BIN:$PATH" bash "$ROOT/one-bit-bureau" motion status) == "reduced" ]]

echo "coordinator motion tests passed"
