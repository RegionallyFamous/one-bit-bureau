#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"
TEST_HOME="$WORK/home"
PLUGIN_ID="io.github.regionallyfamous.paper-jam-84"
SOURCE_ID="paper-jam-84-abcdef123456"
REPO_URL="https://github.com/RegionallyFamous/paper-jam-84.git"
STATE="$TEST_HOME/.local/state/omarchy/plugins/$PLUGIN_ID/install-state.json"
PLUGIN="$TEST_HOME/.config/omarchy/plugins/$PLUGIN_ID"
SOURCE="$TEST_HOME/.local/share/omarchy/theme-sources/$SOURCE_ID"
THEME="$TEST_HOME/.config/omarchy/themes/paper-jam-84"
LOG="$WORK/omarchy.log"

mkdir -p "$BIN" "$PLUGIN/.git" "$(dirname "$STATE")" "$SOURCE/.git" "$SOURCE/themes/paper-jam-84" "$(dirname "$THEME")"
ln -s "$SOURCE/themes/paper-jam-84" "$THEME"

printf '%s\n' '#!/bin/bash' 'printf "%s\n" "$*" >>"$TEST_LOG"' 'exit 0' >"$BIN/omarchy"
chmod +x "$BIN/omarchy"
printf '%s\n' '#!/bin/bash' 'set -euo pipefail' \
  'if [[ $* == *"config --get remote.origin.url"* ]]; then printf "%s\n" "https://github.com/RegionallyFamous/paper-jam-84.git"' \
  'elif [[ $* == *"status --porcelain"* ]]; then exit 0' \
  'elif [[ $* == *"rev-parse HEAD"* ]]; then printf "%040d\n" 1' \
  'else exit 1; fi' >"$BIN/git"
chmod +x "$BIN/git"

write_good_state() {
  jq -n --arg id "$PLUGIN_ID" --arg source "$SOURCE_ID" --arg repo "$REPO_URL" '{
    schemaVersion: 2,
    pluginId: $id,
    product: "Paper Jam ’84",
    theme: "paper-jam-84",
    pluginOwned: true,
    themeOwned: true,
    installed: {
      pluginOrigin: $repo,
      pluginCommit: "0000000000000000000000000000000000000001",
      themeSourceId: $source,
      themeSourceUrl: $repo,
      themeSourceCommit: "0000000000000000000000000000000000000001",
      commandHash: "abc"
    }
  }' >"$STATE"
}

assert_rejected_without_mutation() {
  local description="$1"
  : >"$LOG"
  if HOME="$TEST_HOME" TEST_LOG="$LOG" PATH="$BIN:$PATH" bash "$ROOT/update" --reconcile >"$WORK/update.log" 2>&1; then
    echo "update accepted $description" >&2
    exit 1
  fi
  [[ ! -s $LOG ]] || {
    echo "update mutated Omarchy state for $description" >&2
    cat "$LOG" >&2
    exit 1
  }
}

echo "== update rejects null, mismatched, and unowned source records before mutation"
write_good_state
jq '.installed.themeSourceId = null' "$STATE" >"$STATE.tmp" && mv "$STATE.tmp" "$STATE"
assert_rejected_without_mutation "a null source ID"

write_good_state
jq '.installed.themeSourceUrl = "https://example.invalid/other.git"' "$STATE" >"$STATE.tmp" && mv "$STATE.tmp" "$STATE"
assert_rejected_without_mutation "a mismatched source URL"

write_good_state
jq '.themeOwned = false' "$STATE" >"$STATE.tmp" && mv "$STATE.tmp" "$STATE"
assert_rejected_without_mutation "themeOwned=false"

echo "== update verifies the installed theme link belongs to the source"
write_good_state
rm "$THEME"
mkdir -p "$WORK/unowned-theme"
ln -s "$WORK/unowned-theme" "$THEME"
assert_rejected_without_mutation "an unowned theme link"

echo "update ownership tests passed"
