#!/bin/bash

# omarchy-test-lab:timeout=300

set -Eeuo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

FIXTURE="$ROOT/test/acceptance.d/fixtures/plugin"
PLUGIN_ID=$(jq -er '.id' "$FIXTURE/manifest.json")
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
THEMES_DIR="$HOME/.config/omarchy/themes"
ORIGINAL_THEME=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)
QMLLINT_BIN=$(command -v qmllint || true)
: "${QMLLINT_BIN:=/usr/lib/qt6/bin/qmllint}"

screen_lacks() {
  ! screen_contains "$1"
}

collect_diagnostics() {
  {
    echo "==> plugin catalog"
    omarchy plugin list --json 2>&1 || true
    echo "==> layers"
    hyprctl -j layers 2>&1 || true
    echo "==> clients"
    hyprctl -j clients 2>&1 || true
    echo "==> quickshell log"
    quickshell --no-color log -p "$OMARCHY_PATH/shell" --any-display --tail 320 2>&1 || true
    echo "==> shell journal"
    journalctl --user -b -u omarchy-shell.service --no-pager -n 320 2>&1 || true
  } >"$ARTIFACTS/paper-jam-diagnostics.log"
}

cleanup_paper_jam() {
  trap - ERR
  omarchy-shell shell hide "$PLUGIN_ID" >/dev/null 2>&1 || true
  close_windows '^paper-jam-qa-' || true
  if [[ -n $ORIGINAL_THEME ]]; then
    omarchy theme set "$ORIGINAL_THEME" >/dev/null 2>&1 || true
  fi
  if [[ -d $PLUGIN_DIR ]]; then
    rm -rf "$PLUGIN_DIR"
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi
  rm -rf "$THEMES_DIR/paper-jam-84"
}

handle_unexpected_error() {
  local status=$?
  local line="$1"
  local command="$2"

  trap - ERR
  collect_diagnostics
  screenshot "failure-paper-jam-unexpected-command"
  printf 'not ok - Paper Jam stopped at line %s with status %s: %s\n' "$line" "$status" "$command" >&2
  exit "$status"
}

trap cleanup_paper_jam EXIT
trap 'handle_unexpected_error "$LINENO" "$BASH_COMMAND"' ERR

[[ ! -e $PLUGIN_DIR ]] || fail "Paper Jam is absent before installation"
[[ -x $QMLLINT_BIN ]] || fail "the guest provides qmllint"

mapfile -d '' -t qml_files < <(find "$FIXTURE" -type f -name '*.qml' -print0 | sort -z)
if ! "$QMLLINT_BIN" -I "$OMARCHY_PATH/shell" "${qml_files[@]}" >"$ARTIFACTS/paper-jam-qmllint.log" 2>&1; then
  fail "Paper Jam passes qmllint" "$(<"$ARTIFACTS/paper-jam-qmllint.log")"
fi
pass "Paper Jam passes qmllint"

"$OMARCHY_PATH/bin/omarchy-plugin-validate" "$FIXTURE" || fail "Paper Jam passes the host validator"
pass "Paper Jam passes the host validator"

mkdir -p "$HOME/Desktop" "$THEMES_DIR" "$(dirname "$PLUGIN_DIR")"
mkdir -p "$HOME/Desktop/Projects"
printf 'Paper Jam runtime proof\n' >"$HOME/Desktop/PAPER-JAM-QA.txt"
cp "$FIXTURE/docs/assets/proof-photo.png" "$HOME/Desktop/Paper Jam Photo.png"

printf 'keep target\n' >"$HOME/PAPER-JAM-SYMLINK-TARGET.txt"
ln -s "$HOME/PAPER-JAM-SYMLINK-TARGET.txt" "$HOME/Desktop/Symlink to keep.txt"
python3 "$FIXTURE/components/desktop/bin/desktop-index" --trash "$HOME/Desktop/Symlink to keep.txt"
[[ -f $HOME/PAPER-JAM-SYMLINK-TARGET.txt && ! -e $HOME/Desktop/Symlink\ to\ keep.txt ]] || fail "Trash removes a Desktop symlink without trashing its target"
pass "Trash preserves a Desktop symlink target"

mkdir -p "$HOME/Downloads/applications"
printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Untrusted QA' 'Exec=foot' >"$HOME/Downloads/applications/untrusted-qa.desktop"
chmod +x "$HOME/Downloads/applications/untrusted-qa.desktop"
python3 "$FIXTURE/components/desktop/bin/add-to-desktop" "$HOME/Downloads/applications/untrusted-qa.desktop" >/dev/null
[[ ! -x $HOME/Desktop/Untrusted\ QA.desktop ]] || fail "Downloaded launchers remain untrusted"
python3 "$FIXTURE/components/desktop/bin/desktop-index" | jq -e '.items[] | select(.name == "Untrusted QA") | .trusted == false' >/dev/null || fail "Desktop index reports copied downloaded launcher as untrusted"
pass "Copied downloaded launchers remain untrusted"

cp -a "$FIXTURE" "$PLUGIN_DIR"
cp -a "$FIXTURE/themes/paper-jam-84" "$THEMES_DIR/paper-jam-84"

omarchy-shell shell rescanPlugins >/dev/null
wait_until "Paper Jam is discovered" 15 \
  bash -c "omarchy plugin list --json | jq -e --arg id '$PLUGIN_ID' 'any(.[]; .id == \$id)'"

omarchy plugin enable "$PLUGIN_ID" --section left --after omarchy.menu >/dev/null
wait_until "Paper Jam is enabled" 15 \
  bash -c "omarchy plugin list --json | jq -e --arg id '$PLUGIN_ID' 'any(.[]; .id == \$id and .enabled)'"
wait_until "Paper Jam desktop files are mounted" 20 layer_on_screen desktop-icons
wait_until "Paper Jam dock is mounted" 20 layer_on_screen alumina-dock
wait_until "Paper Jam overview hot corner is resident" 20 layer_on_screen alumina-overview-hot-corner
omarchy-shell regionallyfamous.alumina.dock setAutoHide false >/dev/null
wait_until "Paper Jam dock auto-hide is disabled for visual proof" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.alumina.dock getAutoHide) == 'false' ]]"

omarchy theme set paper-jam-84 >/dev/null
wait_until "Paper Jam ’84 is active" 30 \
  bash -c "grep -Fxq 'paper-jam-84' '$HOME/.local/state/omarchy/current/theme.name'"
sleep 2
screen_lacks "Your config has errors" || fail "Paper Jam applies without a Hyprland config error"
pass "Paper Jam applies without a Hyprland config error"
omarchy-shell notifications dismissAll >/dev/null 2>&1 || true
screenshot "success-paper-jam-01-desktop-dock"

setsid -f foot --app-id=paper-jam-qa-one --title="Paper Jam Notes" >/dev/null 2>&1
setsid -f foot --app-id=paper-jam-qa-two --title="Paper Jam Project" >/dev/null 2>&1
wait_until "the first proof window opens" 20 window_present '^paper-jam-qa-one$'
wait_until "the second proof window opens" 20 window_present '^paper-jam-qa-two$'
sleep 3
omarchy-shell notifications dismissAll >/dev/null 2>&1 || true

omarchy-shell shell summon "$PLUGIN_ID" '{}' >/dev/null
wait_until "Paper Jam overview opens" 20 layer_on_screen alumina-window-overview
wait_until "Paper Jam overview instructions paint" 20 screen_contains "navigate"
sleep 2
screenshot "success-paper-jam-02-overview"

omarchy-shell shell hide "$PLUGIN_ID" >/dev/null
wait_until "Paper Jam overview layer closes" 20 layer_absent alumina-window-overview
wait_until "Paper Jam overview pixels clear" 10 screen_lacks "navigate"

omarchy plugin disable "$PLUGIN_ID" >/dev/null
wait_until "Paper Jam dock unloads" 20 layer_absent alumina-dock
wait_until "Paper Jam desktop service unloads" 20 layer_absent desktop-icons
wait_until "Paper Jam hot corner unloads" 20 layer_absent alumina-overview-hot-corner
hyprctl -j binds | jq -e 'all(.[]; ((.command // "") + " " + (.arg // "")) | contains("regionallyfamous.alumina.dock") | not)' >/dev/null || fail "Paper Jam leaves no dead global app-switcher bindings"
pass "Paper Jam leaves global app-switcher bindings untouched"
screenshot "success-paper-jam-03-disabled-stock-shell"

pass "Paper Jam runtime acceptance passed"
