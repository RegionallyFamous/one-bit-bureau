#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"
TEST_HOME="$WORK/home"
PLUGIN_ID="io.github.regionallyfamous.one-bit-bureau"
SOURCE_ID="one-bit-bureau-abcdef123456"
REPO_URL="https://github.com/RegionallyFamous/one-bit-bureau.git"
STATE="$TEST_HOME/.local/state/omarchy/plugins/$PLUGIN_ID/install-state.json"
PLUGIN="$TEST_HOME/.config/omarchy/plugins/$PLUGIN_ID"
SOURCE="$TEST_HOME/.local/share/omarchy/theme-sources/$SOURCE_ID"
THEME="$TEST_HOME/.config/omarchy/themes/one-bit-bureau"
LOG="$WORK/omarchy.log"
SOURCE_API="$WORK/source-api"

mkdir -p "$BIN" "$SOURCE_API/bin" "$PLUGIN/.git" "$(dirname "$STATE")" "$SOURCE/.git" "$SOURCE/themes/one-bit-bureau" "$(dirname "$THEME")"
ln -s "$SOURCE/themes/one-bit-bureau" "$THEME"
for source_command in inspect install update detach; do
  printf '%s\n' '#!/bin/bash' 'exit 0' >"$SOURCE_API/bin/omarchy-theme-source-$source_command"
  chmod +x "$SOURCE_API/bin/omarchy-theme-source-$source_command"
done
export OMARCHY_PATH="$SOURCE_API"

printf '%s\n' '#!/bin/bash' 'printf "%s\n" "$*" >>"$TEST_LOG"' \
  'if [[ $* == theme\ source\ update* ]]; then printf '\''{"source":{"commit":"0000000000000000000000000000000000000001"}}\n'\''; fi' \
  'exit 0' >"$BIN/omarchy"
chmod +x "$BIN/omarchy"
printf '%s\n' '#!/bin/bash' 'set -euo pipefail' \
  'if [[ $* == *"config --get remote.origin.url"* ]]; then printf "%s\n" "${TEST_GIT_ORIGIN:-https://github.com/RegionallyFamous/one-bit-bureau.git}"' \
  'elif [[ $* == *"status --porcelain"* ]]; then [[ ${TEST_GIT_DIRTY:-0} != 1 ]] || echo dirty' \
  'elif [[ $* == *"rev-parse HEAD"* ]]; then printf "%s\n" "${TEST_GIT_HEAD:-0000000000000000000000000000000000000001}"' \
  'else exit 1; fi' >"$BIN/git"
chmod +x "$BIN/git"

write_good_state() {
  jq -n --arg id "$PLUGIN_ID" --arg source "$SOURCE_ID" --arg repo "$REPO_URL" '{
    schemaVersion: 3,
    pluginId: $id,
    product: "One-Bit Bureau",
    theme: "one-bit-bureau",
    pluginOwned: true,
    themeOwned: true,
    installed: {
      pluginOrigin: $repo,
      pluginCommit: "0000000000000000000000000000000000000001",
      themeSourceId: $source,
      themeSourceUrl: $repo,
      themeSourceCommit: "0000000000000000000000000000000000000001",
      themeInstallMode: "source",
      commandHash: "abc"
    }
  }' >"$STATE"
}

write_good_plugin_link_state() {
  jq -n --arg id "$PLUGIN_ID" --arg repo "$REPO_URL" '{
    schemaVersion: 3,
    pluginId: $id,
    product: "One-Bit Bureau",
    theme: "one-bit-bureau",
    pluginOwned: true,
    themeOwned: true,
    installed: {
      pluginOrigin: $repo,
      pluginCommit: "0000000000000000000000000000000000000001",
      themeSourceId: "",
      themeSourceUrl: $repo,
      themeSourceCommit: "0000000000000000000000000000000000000001",
      themeInstallMode: "plugin-link",
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

echo "== source-mode update uses only its recorded source"
rm "$THEME"
ln -s "$SOURCE/themes/one-bit-bureau" "$THEME"
write_good_state
: >"$LOG"
HOME="$TEST_HOME" TEST_LOG="$LOG" PATH="$BIN:$PATH" bash "$ROOT/update" --reconcile >"$WORK/source-update.log"
grep -Fxq "theme source update $SOURCE_ID --json" "$LOG"
! grep -Fxq "theme update" "$LOG"

echo "== source-mode downgrade fails before plugin mutation"
write_good_state
: >"$LOG"
if HOME="$TEST_HOME" OMARCHY_PATH="" TEST_LOG="$LOG" PATH="$BIN:$PATH" bash "$ROOT/update" --yes >"$WORK/source-api-missing.log" 2>&1; then
  echo "update continued without the required source API" >&2
  exit 1
fi
[[ ! -s $LOG ]]

echo "== update rejects a changed plugin origin before mutation"
mkdir -p "$PLUGIN/themes/one-bit-bureau"
rm "$THEME"
ln -s "$PLUGIN/themes/one-bit-bureau" "$THEME"
write_good_plugin_link_state
export TEST_GIT_ORIGIN="https://example.invalid/not-owned.git"
assert_rejected_without_mutation "a changed plugin origin"
unset TEST_GIT_ORIGIN

echo "== update supports a plugin-linked theme without source commands"
write_good_plugin_link_state
: >"$LOG"
HOME="$TEST_HOME" TEST_LOG="$LOG" PATH="$BIN:$PATH" bash "$ROOT/update" --reconcile >"$WORK/plugin-link-update.log"
[[ ! -s $LOG ]]
jq -e '.installed.themeInstallMode == "plugin-link" and .installed.pluginCommit == .installed.themeSourceCommit' "$STATE" >/dev/null

echo "== plugin-linked update delegates once and never invokes a theme updater"
cp "$ROOT/update" "$PLUGIN/update"
write_good_plugin_link_state
: >"$LOG"
HOME="$TEST_HOME" TEST_LOG="$LOG" PATH="$BIN:$PATH" bash "$ROOT/update" --yes >"$WORK/plugin-link-delegated.log"
grep -Fxq "plugin update $PLUGIN_ID --yes" "$LOG"
! grep -q '^theme source\|^theme update' "$LOG"

write_good_plugin_link_state
rm "$THEME"
ln -s "$WORK/unowned-theme" "$THEME"
assert_rejected_without_mutation "an unowned plugin-linked theme"

write_good_plugin_link_state
rm "$THEME"
mkdir "$THEME"
assert_rejected_without_mutation "a regular theme directory in plugin-link mode"

rm -rf "$THEME"
ln -s "$WORK/missing-theme" "$THEME"
assert_rejected_without_mutation "a dangling plugin-linked theme"

echo "update ownership tests passed"
