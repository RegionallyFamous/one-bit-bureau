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
  } >"$ARTIFACTS/alumina-diagnostics.log"
}

cleanup_alumina() {
  trap - ERR
  omarchy-shell shell hide "$PLUGIN_ID" >/dev/null 2>&1 || true
  close_windows '^alumina-qa-' || true
  if [[ -n $ORIGINAL_THEME ]]; then
    omarchy theme set "$ORIGINAL_THEME" >/dev/null 2>&1 || true
  fi
  if [[ -d $PLUGIN_DIR ]]; then
    rm -rf "$PLUGIN_DIR"
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi
  rm -rf "$THEMES_DIR/alumina-dark" "$THEMES_DIR/alumina-light"
}

handle_unexpected_error() {
  local status=$?
  local line="$1"
  local command="$2"

  trap - ERR
  collect_diagnostics
  screenshot "failure-alumina-unexpected-command"
  printf 'not ok - Alumina stopped at line %s with status %s: %s\n' "$line" "$status" "$command" >&2
  exit "$status"
}

trap cleanup_alumina EXIT
trap 'handle_unexpected_error "$LINENO" "$BASH_COMMAND"' ERR

[[ ! -e $PLUGIN_DIR ]] || fail "Alumina is absent before installation"
[[ -x $QMLLINT_BIN ]] || fail "the guest provides qmllint"

mapfile -d '' -t qml_files < <(find "$FIXTURE" -type f -name '*.qml' -print0 | sort -z)
if ! "$QMLLINT_BIN" -I "$OMARCHY_PATH/shell" "${qml_files[@]}" >"$ARTIFACTS/alumina-qmllint.log" 2>&1; then
  fail "Alumina passes qmllint" "$(<"$ARTIFACTS/alumina-qmllint.log")"
fi
pass "Alumina passes qmllint"

"$OMARCHY_PATH/bin/omarchy-plugin-validate" "$FIXTURE" || fail "Alumina passes the host validator"
pass "Alumina passes the host validator"

mkdir -p "$HOME/Desktop" "$THEMES_DIR" "$(dirname "$PLUGIN_DIR")"
mkdir -p "$HOME/Desktop/Projects"
printf 'Alumina runtime proof\n' >"$HOME/Desktop/ALUMINA-QA.txt"
cp -a "$FIXTURE" "$PLUGIN_DIR"
cp -a "$FIXTURE/themes/alumina-dark" "$THEMES_DIR/alumina-dark"
cp -a "$FIXTURE/themes/alumina-light" "$THEMES_DIR/alumina-light"

omarchy-shell shell rescanPlugins >/dev/null
wait_until "Alumina is discovered" 15 \
  bash -c "omarchy plugin list --json | jq -e --arg id '$PLUGIN_ID' 'any(.[]; .id == \$id)'"

omarchy plugin enable "$PLUGIN_ID" --section left --after omarchy.menu >/dev/null
wait_until "Alumina is enabled" 15 \
  bash -c "omarchy plugin list --json | jq -e --arg id '$PLUGIN_ID' 'any(.[]; .id == \$id and .enabled)'"
wait_until "Alumina desktop files are mounted" 20 layer_on_screen desktop-icons
wait_until "Alumina dock is mounted" 20 layer_on_screen alumina-dock
wait_until "Alumina overview hot corner is resident" 20 layer_on_screen alumina-overview-hot-corner
omarchy-shell regionallyfamous.alumina.dock setAutoHide false >/dev/null
wait_until "Alumina dock auto-hide is disabled for visual proof" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.alumina.dock getAutoHide) == 'false' ]]"

omarchy theme set alumina-dark >/dev/null
wait_until "Alumina Dark is active" 30 \
  bash -c "grep -Fxq 'alumina-dark' '$HOME/.local/state/omarchy/current/theme.name'"
sleep 2
screen_lacks "Your config has errors" || fail "Alumina Dark applies without a Hyprland config error"
pass "Alumina Dark applies without a Hyprland config error"
omarchy-shell notifications dismissAll >/dev/null 2>&1 || true
screenshot "success-alumina-01-dark-desktop-dock"

setsid -f foot --app-id=alumina-qa-one --title="Alumina Notes" >/dev/null 2>&1
setsid -f foot --app-id=alumina-qa-two --title="Alumina Project" >/dev/null 2>&1
wait_until "the first proof window opens" 20 window_present '^alumina-qa-one$'
wait_until "the second proof window opens" 20 window_present '^alumina-qa-two$'
sleep 3
omarchy-shell notifications dismissAll >/dev/null 2>&1 || true

omarchy-shell shell summon "$PLUGIN_ID" '{}' >/dev/null
wait_until "Alumina overview opens" 20 layer_on_screen alumina-window-overview
wait_until "Alumina overview instructions paint" 20 screen_contains "navigate"
sleep 2
screenshot "success-alumina-02-dark-overview"

omarchy-shell shell hide "$PLUGIN_ID" >/dev/null
wait_until "Alumina overview layer closes" 20 layer_absent alumina-window-overview
wait_until "Alumina overview pixels clear" 10 screen_lacks "navigate"

omarchy theme set alumina-light >/dev/null
wait_until "Alumina Light is active" 30 \
  bash -c "grep -Fxq 'alumina-light' '$HOME/.local/state/omarchy/current/theme.name'"
sleep 3
screen_lacks "Your config has errors" || fail "Alumina Light applies without a Hyprland config error"
pass "Alumina Light applies without a Hyprland config error"
screenshot "success-alumina-03-light-desktop-dock"

omarchy-shell shell summon "$PLUGIN_ID" '{}' >/dev/null
wait_until "Alumina Light overview opens" 20 layer_on_screen alumina-window-overview
sleep 2
screenshot "success-alumina-04-light-overview"
omarchy-shell shell hide "$PLUGIN_ID" >/dev/null
wait_until "Alumina Light overview closes" 20 layer_absent alumina-window-overview

omarchy plugin disable "$PLUGIN_ID" >/dev/null
wait_until "Alumina dock unloads" 20 layer_absent alumina-dock
wait_until "Alumina desktop service unloads" 20 layer_absent desktop-icons
wait_until "Alumina hot corner unloads" 20 layer_absent alumina-overview-hot-corner
screenshot "success-alumina-05-disabled-stock-shell"

pass "Alumina runtime acceptance passed"
