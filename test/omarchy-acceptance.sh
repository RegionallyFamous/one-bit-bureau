#!/bin/bash

# omarchy-test-lab:timeout=300
# The Test Lab installs this file as test/acceptance.d/plugin-test.sh beside
# Omarchy's base-test.sh and stages this repository at fixtures/plugin.

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

dock_has_seeded_items() {
  local count
  count=$(omarchy-shell regionallyfamous.paper-jam-84.dock getItemCount 2>/dev/null || true)
  [[ $count =~ ^[0-9]+$ ]] && (( count >= 3 ))
}

dock_has_rendered_icons() {
  local count
  count=$(omarchy-shell regionallyfamous.paper-jam-84.dock getReadyIconCount 2>/dev/null || true)
  [[ $count =~ ^[0-9]+$ ]] && (( count >= 3 ))
}

dock_has_normalized_pack_icons() {
  local count
  count=$(omarchy-shell regionallyfamous.paper-jam-84.dock getNormalizedPackIconCount 2>/dev/null || true)
  [[ $count =~ ^[0-9]+$ ]] && (( count >= 3 ))
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
python3 "$FIXTURE/components/desktop/bin/desktop-index" | jq -e --arg photo "$HOME/Desktop/Paper Jam Photo.png" '.items[] | select(.path == $photo) | .kind == "image" and .preview == $photo' >/dev/null || fail "Desktop index exposes the real photo as a safe local preview"
pass "Desktop index exposes the real photo as a safe local preview"

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
wait_until "Paper Jam dock is mounted" 20 layer_on_screen paper-jam-84-dock
wait_until "Paper Jam overview hot corner is resident" 20 layer_on_screen paper-jam-84-overview-hot-corner
omarchy-shell regionallyfamous.paper-jam-84.dock setAutoHide false >/dev/null
wait_until "Paper Jam dock auto-hide is disabled for visual proof" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.paper-jam-84.dock getAutoHide) == 'false' ]]"
wait_until "Paper Jam seeds a useful first-run dock" 15 dock_has_seeded_items
wait_until "Paper Jam renders every seeded dock icon" 15 dock_has_rendered_icons
wait_until "Paper Jam normalizes every seeded dock icon" 15 dock_has_normalized_pack_icons
[[ $(omarchy-shell regionallyfamous.paper-jam-84.dock getIconSize) == "48" ]] || fail "Paper Jam uses the approved 48px dock icon box"
pass "Paper Jam uses the approved 48px dock icon box"

run_helper="$PLUGIN_DIR/components/dock/scripts/paper-jam-run"
kill_ready_pid_file="$ARTIFACTS/paper-jam-kill-ready.pid"
python3 "$run_helper" 10000 100 -- python3 -c 'import os, pathlib, signal, sys, time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)' "$kill_ready_pid_file" &
kill_ready_controller=$!
for _ in {1..100}; do
  [[ -s $kill_ready_pid_file ]] && break
  sleep 0.02
done
[[ -s $kill_ready_pid_file ]] || fail "Paper Jam containment reaches its ready gate"
kill_ready_child=$(<"$kill_ready_pid_file")
kill -KILL "$kill_ready_controller"
wait "$kill_ready_controller" 2>/dev/null || true
wait_until "Paper Jam kernel containment reaps a ready task after controller SIGKILL" 10 \
  bash -c "! kill -0 '$kill_ready_child' 2>/dev/null"

pre_ready_pid_file="$ARTIFACTS/paper-jam-kill-before-ready.pid"
PAPER_JAM_RUN_TEST_GATE_DELAY_MS=600 python3 "$run_helper" 10000 100 -- python3 -c 'import os, pathlib, sys, time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(60)' "$pre_ready_pid_file" &
pre_ready_controller=$!
pre_ready_child=""
for _ in {1..100}; do
  if [[ -r /proc/$pre_ready_controller/task/$pre_ready_controller/children ]]; then
    pre_ready_child=$(</proc/$pre_ready_controller/task/$pre_ready_controller/children)
    pre_ready_child=${pre_ready_child%% *}
  fi
  [[ -n $pre_ready_child ]] && break
  sleep 0.01
done
[[ -n $pre_ready_child ]] || fail "Paper Jam exposes the pre-ready containment fixture"
kill -KILL "$pre_ready_controller"
wait "$pre_ready_controller" 2>/dev/null || true
wait_until "Paper Jam fail-closed gate reaps a pre-ready task after controller SIGKILL" 10 \
  bash -c "! kill -0 '$pre_ready_child' 2>/dev/null"
[[ ! -e $pre_ready_pid_file ]] || fail "Paper Jam never executes a task whose containment owner died before readiness"
pass "Paper Jam contains controller death before and after readiness"

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
wait_until "Paper Jam overview opens" 20 layer_on_screen paper-jam-84-window-overview
wait_until "Paper Jam overview instructions paint" 20 screen_contains "navigate"
sleep 2
screenshot "success-paper-jam-02-overview"

omarchy-shell shell hide "$PLUGIN_ID" >/dev/null
wait_until "Paper Jam overview layer closes" 20 layer_absent paper-jam-84-window-overview
wait_until "Paper Jam overview pixels clear" 10 screen_lacks "navigate"

cp "$FIXTURE/test/stubborn-state-helper.py" "$PLUGIN_DIR/components/dock/scripts/paper-jam-state"
stubborn_pid_file="$HOME/.config/omarchy/paper-jam-84/stubborn-state-helper.pid"
for _ in {1..100}; do
  [[ -s $stubborn_pid_file ]] && break
  sleep 0.02
done
[[ -s $stubborn_pid_file ]] || fail "Paper Jam starts the active-unload containment fixture"
stubborn_pid=$(<"$stubborn_pid_file")
omarchy plugin disable "$PLUGIN_ID" >/dev/null
wait_until "Paper Jam dock unloads" 20 layer_absent paper-jam-84-dock
wait_until "Paper Jam desktop service unloads" 20 layer_absent desktop-icons
wait_until "Paper Jam hot corner unloads" 20 layer_absent paper-jam-84-overview-hot-corner
wait_until "Paper Jam reaps an active TERM-ignoring helper on unload" 10 \
  bash -c "! kill -0 '$stubborn_pid' 2>/dev/null"
if pgrep -f "paper-jam-run.*$PLUGIN_DIR" >/dev/null 2>&1; then
  fail "Paper Jam leaves no helper controller behind after unload"
fi
pass "Paper Jam contains and reaps active helpers on unload"
hyprctl -j binds | jq -e 'all(.[]; ((.command // "") + " " + (.arg // "")) | contains("regionallyfamous.paper-jam-84.dock") | not)' >/dev/null || fail "Paper Jam leaves no dead global app-switcher bindings"
pass "Paper Jam leaves global app-switcher bindings untouched"
screenshot "success-paper-jam-03-disabled-stock-shell"

pass "Paper Jam runtime acceptance passed"
