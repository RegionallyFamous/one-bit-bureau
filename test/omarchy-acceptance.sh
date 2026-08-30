#!/bin/bash

# omarchy-test-lab:requires=pointer
# omarchy-test-lab:timeout=600
# The Test Lab installs this file as test/acceptance.d/plugin-test.sh beside
# Omarchy's base-test.sh and stages this repository at fixtures/plugin.

set -Eeuo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

FIXTURE="$ROOT/test/acceptance.d/fixtures/plugin"
PLUGIN_ID=$(jq -er '.id' "$FIXTURE/manifest.json")
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
THEMES_DIR="$HOME/.config/omarchy/themes"
THEME_NAME="one-bit-bureau"
THEME_TARGET="$THEMES_DIR/$THEME_NAME"
STATE_DIR="$HOME/.local/state/omarchy/plugins/$PLUGIN_ID"
STATE_FILE="$STATE_DIR/install-state.json"
BUREAU_CONFIG="$HOME/.config/omarchy/one-bit-bureau"
FONT_TARGET="$HOME/.local/share/fonts/one-bit-bureau"
COMMAND_TARGET="$HOME/.local/bin/one-bit-bureau"
PUBLIC_REPO_URL="https://github.com/RegionallyFamous/one-bit-bureau.git"
THEME_SOURCES_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy/theme-sources"
THEME_SOURCE_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/theme-sources"
ORIGINAL_THEME=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)
ORIGINAL_BAR_POSITION=$(jq -r '.bar.position // "top"' "$HOME/.config/omarchy/shell.json" 2>/dev/null || echo top)
ORIGINAL_BAR_TRANSPARENT=$(jq -r '.bar.transparent // false' "$HOME/.config/omarchy/shell.json" 2>/dev/null || echo false)
QMLLINT_BIN=$(command -v qmllint || true)
: "${QMLLINT_BIN:=/usr/lib/qt6/bin/qmllint}"

BASELINE_DIR=$(mktemp -d "$ARTIFACTS/one-bit-bureau-baseline.XXXXXX")
ORIGINAL_ABOUT_PRESENT=false
ORIGINAL_SCREENSAVER_PRESENT=false
if [[ -f $HOME/.config/omarchy/branding/about.txt ]]; then
  ORIGINAL_ABOUT_PRESENT=true
  cp -- "$HOME/.config/omarchy/branding/about.txt" "$BASELINE_DIR/about.txt"
fi
if [[ -f $HOME/.config/omarchy/branding/screensaver.txt ]]; then
  ORIGINAL_SCREENSAVER_PRESENT=true
  cp -- "$HOME/.config/omarchy/branding/screensaver.txt" "$BASELINE_DIR/screensaver.txt"
fi

PUBLIC_SOURCE_ID=""
PUBLIC_SOURCE_PATH=""
public_lifecycle_active=false

screen_lacks() {
  ! screen_contains "$1"
}

icon_manager_has_terminal() {
  screen_contains "Foot" || screen_contains "Terminal"
}

dock_has_seeded_items() {
  local count
  count=$(omarchy-shell regionallyfamous.one-bit-bureau.dock getItemCount 2>/dev/null || true)
  [[ $count =~ ^[0-9]+$ ]] && (( count >= 3 ))
}

dock_has_rendered_icons() {
  local count
  count=$(omarchy-shell regionallyfamous.one-bit-bureau.dock getReadyIconCount 2>/dev/null || true)
  [[ $count =~ ^[0-9]+$ ]] && (( count >= 3 ))
}

dock_has_normalized_pack_icons() {
  local count
  count=$(omarchy-shell regionallyfamous.one-bit-bureau.dock getNormalizedPackIconCount 2>/dev/null || true)
  [[ $count =~ ^[0-9]+$ ]] && (( count >= 3 ))
}

pointer_is_near() {
  local expected_x="$1"
  local expected_y="$2"
  local actual_x actual_y

  actual_x=$(hyprctl -j cursorpos | jq -er '.x | round') || return 1
  actual_y=$(hyprctl -j cursorpos | jq -er '.y | round') || return 1
  (( actual_x >= expected_x - 3 && actual_x <= expected_x + 3
    && actual_y >= expected_y - 3 && actual_y <= expected_y + 3 ))
}

move_pointer_to() {
  local target_x="$1"
  local target_y="$2"
  local description="$3"
  local current_x current_y delta_x delta_y attempt

  command -v ydotool >/dev/null 2>&1 || fail "pointer automation is available"
  for (( attempt = 0; attempt < 6; attempt++ )); do
    if pointer_is_near "$target_x" "$target_y"; then
      pass "$description"
      return 0
    fi
    current_x=$(hyprctl -j cursorpos | jq -er '.x | round')
    current_y=$(hyprctl -j cursorpos | jq -er '.y | round')
    delta_x=$((target_x - current_x))
    delta_y=$((target_y - current_y))
    ydotool mousemove -- "$delta_x" "$delta_y" >/dev/null || fail "$description"
    sleep 0.25
  done
  fail "$description"
}

focus_empty_desktop() {
  local target_x target_y
  target_x=$(hyprctl -j monitors | jq -er '.[0] | (.x + (.width / .scale) / 2) | floor')
  target_y=$(hyprctl -j monitors | jq -er '.[0] | (.y + (.height / .scale) * 0.55) | floor')
  move_pointer_to "$target_x" "$target_y" "the pointer reaches empty desktop space"
  ydotool click 0xC0 >/dev/null || fail "the virtual pointer focuses the desktop"
  sleep 0.3
}

select_desktop_item_by_id() {
  local item_id="$1"
  local index tabs i

  index=$(python3 "$PLUGIN_DIR/components/desktop/bin/desktop-index" |
    jq -er --arg id "$item_id" '.items | map(.id) | index($id)')
  tabs=$((index + 1))
  focus_empty_desktop
  for (( i = 0; i < tabs; i++ )); do
    wtype -k Tab
  done
  sleep 0.3
}

decoded_pixel_hash() {
  local image="$1"
  ffmpeg -v error -i "$image" -map 0:v:0 -f md5 - 2>/dev/null | sed -n 's/^MD5=//p'
}

capture_photo_inner_pixels() {
  local destination="$1"
  local record screen_name local_x local_y monitor_x monitor_y crop_x crop_y

  record=$(jq -er --arg id "One-Bit Bureau Photo.png" '
    to_entries[] | select(.value[$id] != null) | [.key, .value[$id].x, .value[$id].y] | @tsv
  ' "$BUREAU_CONFIG/desktop-icon-positions.json" | head -n 1)
  read -r screen_name local_x local_y <<<"$record"
  monitor_x=$(hyprctl -j monitors | jq -er --arg name "$screen_name" '.[] | select(.name == $name) | .x | floor')
  monitor_y=$(hyprctl -j monitors | jq -er --arg name "$screen_name" '.[] | select(.name == $name) | .y | floor')

  # The 40x40 center lies wholly inside the photo's constant 54x54 Image.
  # Selection changes only the surrounding 72x72 enclosure and name rail.
  crop_x=$((monitor_x + local_x + 40))
  crop_y=$((monitor_y + local_y + 22))
  timeout 10 grim -g "${crop_x},${crop_y} 40x40" "$destination" 2>/dev/null ||
    fail "the photo's inner pixels are captured"
}

public_plugin_absent() {
  ! omarchy plugin list --json | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id)'
}

assert_branding_restored() {
  if [[ $ORIGINAL_ABOUT_PRESENT == true ]]; then
    cmp -s "$BASELINE_DIR/about.txt" "$HOME/.config/omarchy/branding/about.txt" || return 1
  else
    [[ ! -e $HOME/.config/omarchy/branding/about.txt ]] || return 1
  fi
  if [[ $ORIGINAL_SCREENSAVER_PRESENT == true ]]; then
    cmp -s "$BASELINE_DIR/screensaver.txt" "$HOME/.config/omarchy/branding/screensaver.txt" || return 1
  else
    [[ ! -e $HOME/.config/omarchy/branding/screensaver.txt ]] || return 1
  fi
}

assert_public_commit_alignment() {
  local plugin_commit source_commit state_plugin_commit state_source_commit remote_commit

  plugin_commit=$(git -C "$PLUGIN_DIR" rev-parse HEAD)
  source_commit=$(git -C "$PUBLIC_SOURCE_PATH" rev-parse HEAD)
  state_plugin_commit=$(jq -er '.installed.pluginCommit' "$STATE_FILE")
  state_source_commit=$(jq -er '.installed.themeSourceCommit' "$STATE_FILE")
  remote_commit=$(git ls-remote "$PUBLIC_REPO_URL" refs/heads/main | awk 'NR == 1 { print $1 }')
  [[ -n $remote_commit && $plugin_commit == "$remote_commit" &&
    $source_commit == "$plugin_commit" &&
    $state_plugin_commit == "$plugin_commit" &&
    $state_source_commit == "$plugin_commit" ]]
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
  } >"$ARTIFACTS/one-bit-bureau-diagnostics.log"
}

cleanup_one_bit_bureau() {
  trap - ERR
  omarchy-shell shell hide "$PLUGIN_ID" >/dev/null 2>&1 || true
  omarchy-shell lock hidePreview >/dev/null 2>&1 || true
  omarchy-shell shell hide omarchy.menu >/dev/null 2>&1 || true
  omarchy-shell notifications dismissAll >/dev/null 2>&1 || true
  close_windows '^one-bit-bureau-qa-' || true
  if [[ $public_lifecycle_active == true && -f $STATE_FILE ]]; then
    if [[ -x $COMMAND_TARGET ]]; then
      "$COMMAND_TARGET" remove >/dev/null 2>&1 || true
    elif [[ -f $PLUGIN_DIR/uninstall ]]; then
      bash "$PLUGIN_DIR/uninstall" >/dev/null 2>&1 || true
    fi
  fi
  if [[ -n $ORIGINAL_THEME ]]; then
    omarchy theme set "$ORIGINAL_THEME" >/dev/null 2>&1 || true
  fi
  if [[ -d $PLUGIN_DIR ]]; then
    rm -rf "$PLUGIN_DIR"
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi
  rm -rf "$THEME_TARGET"
}

handle_unexpected_error() {
  local status=$?
  local line="$1"
  local command="$2"

  trap - ERR
  collect_diagnostics
  screenshot "failure-one-bit-bureau-unexpected-command"
  printf 'not ok - One-Bit Bureau stopped at line %s with status %s: %s\n' "$line" "$status" "$command" >&2
  exit "$status"
}

trap cleanup_one_bit_bureau EXIT
trap 'handle_unexpected_error "$LINENO" "$BASH_COMMAND"' ERR

[[ ! -e $PLUGIN_DIR ]] || fail "One-Bit Bureau is absent before installation"
[[ ! -e $THEME_TARGET && ! -e $STATE_FILE && ! -e $FONT_TARGET && ! -e $COMMAND_TARGET ]] ||
  fail "One-Bit Bureau owned install targets are absent before installation"
[[ -x $QMLLINT_BIN ]] || fail "the guest provides qmllint"
command -v ffmpeg >/dev/null 2>&1 || fail "the guest provides ffmpeg for decoded photo-pixel comparison"

fixture_acceptance_hash=$(sha256sum "$FIXTURE/test/omarchy-acceptance.sh" | awk '{print $1}')
[[ -n $fixture_acceptance_hash ]] || fail "the fixture acceptance hash is available"

mapfile -d '' -t qml_files < <(find "$FIXTURE" -type f -name '*.qml' -print0 | sort -z)
if ! "$QMLLINT_BIN" -I "$OMARCHY_PATH/shell" "${qml_files[@]}" >"$ARTIFACTS/one-bit-bureau-qmllint.log" 2>&1; then
  fail "One-Bit Bureau passes qmllint" "$(<"$ARTIFACTS/one-bit-bureau-qmllint.log")"
fi
pass "One-Bit Bureau passes qmllint"

"$OMARCHY_PATH/bin/omarchy-plugin-validate" "$FIXTURE" || fail "One-Bit Bureau passes the host validator"
pass "One-Bit Bureau passes the host validator"

mkdir -p "$HOME/Desktop" "$THEMES_DIR" "$(dirname "$PLUGIN_DIR")"
mkdir -p "$HOME/Desktop/Projects"
printf 'One-Bit Bureau runtime proof\n' >"$HOME/Desktop/ONE-BIT-BUREAU-QA.txt"
cp "$FIXTURE/docs/assets/proof-photo.png" "$HOME/Desktop/One-Bit Bureau Photo.png"
python3 "$FIXTURE/components/desktop/bin/desktop-index" | jq -e --arg photo "$HOME/Desktop/One-Bit Bureau Photo.png" '.items[] | select(.path == $photo) | .kind == "image" and .preview == $photo' >/dev/null || fail "Desktop index exposes the real photo as a safe local preview"
pass "Desktop index exposes the real photo as a safe local preview"

printf 'keep target\n' >"$HOME/ONE-BIT-BUREAU-SYMLINK-TARGET.txt"
ln -s "$HOME/ONE-BIT-BUREAU-SYMLINK-TARGET.txt" "$HOME/Desktop/Symlink to keep.txt"
python3 "$FIXTURE/components/desktop/bin/desktop-index" --trash "$HOME/Desktop/Symlink to keep.txt"
[[ -f $HOME/ONE-BIT-BUREAU-SYMLINK-TARGET.txt && ! -e $HOME/Desktop/Symlink\ to\ keep.txt ]] || fail "Trash removes a Desktop symlink without trashing its target"
pass "Trash preserves a Desktop symlink target"

mkdir -p "$HOME/Downloads/applications"
printf '%s\n' \
  '[Desktop Entry]' \
  'Type=Application' \
  'Name=Untrusted QA' \
  'Exec=foot --app-id=one-bit-bureau-qa-trusted --title=Trusted-Launcher' \
  >"$HOME/Downloads/applications/untrusted-qa.desktop"
chmod +x "$HOME/Downloads/applications/untrusted-qa.desktop"
python3 "$FIXTURE/components/desktop/bin/add-to-desktop" "$HOME/Downloads/applications/untrusted-qa.desktop" >/dev/null
[[ ! -x $HOME/Desktop/Untrusted\ QA.desktop ]] || fail "Downloaded launchers remain untrusted"
python3 "$FIXTURE/components/desktop/bin/desktop-index" | jq -e '.items[] | select(.name == "Untrusted QA") | .trusted == false' >/dev/null || fail "Desktop index reports copied downloaded launcher as untrusted"
pass "Copied downloaded launchers remain untrusted"

cp -a "$FIXTURE" "$PLUGIN_DIR"
cp -a "$FIXTURE/themes/one-bit-bureau" "$THEMES_DIR/one-bit-bureau"

omarchy-shell shell rescanPlugins >/dev/null
wait_until "One-Bit Bureau is discovered" 15 \
  bash -c "omarchy plugin list --json | jq -e --arg id '$PLUGIN_ID' 'any(.[]; .id == \$id)'"

omarchy plugin enable "$PLUGIN_ID" --section left --after omarchy.menu >/dev/null
wait_until "One-Bit Bureau is enabled" 15 \
  bash -c "omarchy plugin list --json | jq -e --arg id '$PLUGIN_ID' 'any(.[]; .id == \$id and .enabled)'"
wait_until "One-Bit Bureau desktop files are mounted" 20 layer_on_screen one-bit-bureau-desktop
wait_until "One-Bit Bureau dock is mounted" 20 layer_on_screen one-bit-bureau-dock
wait_until "One-Bit Bureau overview hot corner is resident" 20 layer_on_screen one-bit-bureau-overview-hot-corner
omarchy-shell regionallyfamous.one-bit-bureau.dock setAutoHide false >/dev/null
wait_until "One-Bit Bureau dock auto-hide is disabled for visual proof" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getAutoHide) == 'false' ]]"
wait_until "One-Bit Bureau seeds a useful first-run dock" 15 dock_has_seeded_items
wait_until "One-Bit Bureau renders every seeded dock icon" 15 dock_has_rendered_icons
wait_until "One-Bit Bureau normalizes every seeded dock icon" 15 dock_has_normalized_pack_icons
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock getIconSize) == "48" ]] || fail "One-Bit Bureau uses the approved 48px dock icon box"
pass "One-Bit Bureau uses the approved 48px dock icon box"
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock getMaxIconCenterOffset) == "0" ]] || fail "One-Bit Bureau centers dock artwork on the shelf axis"
pass "One-Bit Bureau centers dock artwork on the shelf axis"

run_helper="$PLUGIN_DIR/components/dock/scripts/one-bit-bureau-run"
kill_ready_pid_file="$ARTIFACTS/one-bit-bureau-kill-ready.pid"
python3 "$run_helper" 10000 100 -- python3 -c 'import os, pathlib, signal, sys, time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)' "$kill_ready_pid_file" &
kill_ready_controller=$!
for _ in {1..100}; do
  [[ -s $kill_ready_pid_file ]] && break
  sleep 0.02
done
[[ -s $kill_ready_pid_file ]] || fail "One-Bit Bureau containment reaches its ready gate"
kill_ready_child=$(<"$kill_ready_pid_file")
kill -KILL "$kill_ready_controller"
wait "$kill_ready_controller" 2>/dev/null || true
wait_until "One-Bit Bureau kernel containment reaps a ready task after controller SIGKILL" 10 \
  bash -c "! kill -0 '$kill_ready_child' 2>/dev/null"

pre_ready_pid_file="$ARTIFACTS/one-bit-bureau-kill-before-ready.pid"
ONE_BIT_BUREAU_RUN_TEST_GATE_DELAY_MS=600 python3 "$run_helper" 10000 100 -- python3 -c 'import os, pathlib, sys, time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(60)' "$pre_ready_pid_file" &
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
[[ -n $pre_ready_child ]] || fail "One-Bit Bureau exposes the pre-ready containment fixture"
kill -KILL "$pre_ready_controller"
wait "$pre_ready_controller" 2>/dev/null || true
wait_until "One-Bit Bureau fail-closed gate reaps a pre-ready task after controller SIGKILL" 10 \
  bash -c "! kill -0 '$pre_ready_child' 2>/dev/null"
[[ ! -e $pre_ready_pid_file ]] || fail "One-Bit Bureau never executes a task whose containment owner died before readiness"
pass "One-Bit Bureau contains controller death before and after readiness"

omarchy theme set one-bit-bureau >/dev/null
wait_until "One-Bit Bureau is active" 30 \
  bash -c "grep -Fxq 'one-bit-bureau' '$HOME/.local/state/omarchy/current/theme.name'"
sleep 2
screen_lacks "Your config has errors" || fail "One-Bit Bureau applies without a Hyprland config error"
pass "One-Bit Bureau applies without a Hyprland config error"
omarchy-shell notifications dismissAll >/dev/null 2>&1 || true

# Pointer-enabled Test Lab guests currently expose one fixed output. Assert
# correct ownership on that output here; 16:9, ultrawide, and multi-output
# mutation remain host-level Omarchy acceptance responsibilities because the
# plugin harness has no supported output-reconfiguration helper.
(( $(hyprctl -j monitors | jq 'length') == 1 )) || fail "the pointer lane exposes one deterministic guest output"
monitor_name=$(hyprctl -j monitors | jq -er '.[0].name')
desktop_layer_count=$(hyprctl -j layers | jq '[.. | objects | select(.namespace? == "one-bit-bureau-desktop")] | length')
(( desktop_layer_count == 1 )) || fail "One-Bit Bureau owns exactly one desktop layer on the guest output"
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock getScreen) == "$monitor_name" ]] ||
  fail "One-Bit Bureau assigns its dock to the guest output"
pass "One-Bit Bureau owns the fixed Test Lab output without duplicate surfaces"

wait_until "One-Bit Bureau saves a position for the real photo" 15 \
  bash -c "jq -e --arg id 'One-Bit Bureau Photo.png' 'any(to_entries[]; .value[\$id] != null)' '$BUREAU_CONFIG/desktop-icon-positions.json'"
focus_empty_desktop
screenshot "success-one-bit-bureau-01-photo-idle"
capture_photo_inner_pixels "$ARTIFACTS/one-bit-bureau-photo-idle-inner.png"

select_desktop_item_by_id "One-Bit Bureau Photo.png"
sleep 1
screenshot "success-one-bit-bureau-02-photo-selected"
capture_photo_inner_pixels "$ARTIFACTS/one-bit-bureau-photo-selected-inner.png"
idle_photo_hash=$(decoded_pixel_hash "$ARTIFACTS/one-bit-bureau-photo-idle-inner.png")
selected_photo_hash=$(decoded_pixel_hash "$ARTIFACTS/one-bit-bureau-photo-selected-inner.png")
[[ -n $idle_photo_hash && $idle_photo_hash == "$selected_photo_hash" ]] ||
  fail "selecting a real photo leaves its inner pixels unchanged"
pass "One-Bit Bureau encloses a selected real photo without changing the photo pixels"

wtype -M shift -k F10 -m shift
wait_until "the desktop keyboard context menu opens" 10 screen_contains "Show in Files"
screenshot "success-one-bit-bureau-03-desktop-keyboard-context-menu"
wtype -k Escape
wait_until "the desktop keyboard context menu closes" 10 screen_lacks "Show in Files"

select_desktop_item_by_id "Untrusted QA.desktop"
wtype -k Return
wait_until "the untrusted launcher confirmation opens from the keyboard" 10 screen_contains "Untrusted launcher"
screenshot "success-one-bit-bureau-04-untrusted-launcher-confirmation"
wtype -k Return
wait_until "Enter safely cancels the trust prompt" 10 screen_lacks "Untrusted launcher"
[[ ! -x $HOME/Desktop/Untrusted\ QA.desktop ]] || fail "Enter never trusts an untrusted launcher"

wtype -k Return
wait_until "the trust prompt reopens" 10 screen_contains "Untrusted launcher"
wtype -k Tab
wtype -k Space
wait_until "keyboard trust marks the launcher executable" 10 test -x "$HOME/Desktop/Untrusted QA.desktop"
wait_until "keyboard trust opens the launcher" 20 window_present '^one-bit-bureau-qa-trusted$'
pass "One-Bit Bureau's trust flow keeps Cancel safe and requires an explicit keyboard choice"
close_windows '^one-bit-bureau-qa-trusted$'
wait_until "the trusted-launcher proof window closes" 10 window_absent '^one-bit-bureau-qa-trusted$'

[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock openMenuFirst) == "true" ]] ||
  fail "the dock exposes its first app menu"
wait_until "the dock app menu opens" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getMenuOpen) == 'true' ]]"
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock getMenuCurrentAction) == "setIcon" ]] ||
  fail "the dock menu starts on Get Info"
wtype -k End
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock getMenuCurrentAction) == "toggleAutoHide" ]] ||
  fail "End reaches the last enabled dock command"
wtype -k Up
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock getMenuCurrentAction) == "manageIcons" ]] ||
  fail "Up skips dock-menu separators and reaches Manage Icons"
screenshot "success-one-bit-bureau-05-dock-keyboard-menu"
wtype -k Return
wait_until "Manage Icons opens from the dock keyboard menu" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getIconPickerOpen) == 'true' ]]"
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock getIconPickerMode) == "manage" ]] ||
  fail "the dock keyboard menu opens manager mode"
wtype 'foot'
wait_until "the icon manager keyboard search finds the terminal app" 10 icon_manager_has_terminal
wtype -k Down
wtype -k Return
wait_until "the icon manager keyboard opens an app's icon picker" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getIconPickerMode) == 'picker' ]]"
screenshot "success-one-bit-bureau-06-icon-picker-keyboard"
omarchy-shell regionallyfamous.one-bit-bureau.dock closeManageIcons >/dev/null
wait_until "the icon picker closes through its stable dock API" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getIconPickerOpen) == 'false' ]]"

[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock openManageIcons) == "true" ]] ||
  fail "the dock opens Manage Icons through its public IPC method"
wait_until "Manage Icons IPC opens manager mode" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getIconPickerOpen) == 'true' && \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getIconPickerMode) == 'manage' ]]"
sleep 1
screenshot "success-one-bit-bureau-07-icon-manager-ipc"
wtype -k Escape
wait_until "Escape closes Manage Icons" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getIconPickerOpen) == 'false' ]]"

setsid -f foot --app-id=one-bit-bureau-qa-one --title="One-Bit Bureau Notes" >/dev/null 2>&1
setsid -f foot --app-id=one-bit-bureau-qa-two --title="One-Bit Bureau Project" >/dev/null 2>&1
wait_until "the first proof window opens" 20 window_present '^one-bit-bureau-qa-one$'
wait_until "the second proof window opens" 20 window_present '^one-bit-bureau-qa-two$'
sleep 3
omarchy-shell notifications dismissAll >/dev/null 2>&1 || true

monitor_width=$(hyprctl -j monitors | jq -er '.[0] | (.width / .scale) | floor')
monitor_height=$(hyprctl -j monitors | jq -er '.[0] | (.height / .scale) | floor')
dock_hover_y=$((monitor_height - 44))
preview_found=false
for (( dock_hover_x = monitor_width / 2 - 240; dock_hover_x <= monitor_width / 2 + 240; dock_hover_x += 24 )); do
  move_pointer_to "$dock_hover_x" "$dock_hover_y" "the pointer probes a dock preview target"
  sleep 0.35
  if layer_on_screen one-bit-bureau-dock-preview; then
    preview_found=true
    break
  fi
done
[[ $preview_found == true ]] || fail "hovering a running dock app opens its window preview"
pass "hovering a running dock app opens its window preview"
screenshot "success-one-bit-bureau-08-dock-window-preview"
move_pointer_to $((monitor_width / 2)) $((monitor_height / 2)) "the pointer leaves the dock preview"
wait_until "the dock window preview closes" 10 layer_absent one-bit-bureau-dock-preview

omarchy-shell regionallyfamous.one-bit-bureau.dock setAutoHide true >/dev/null
wait_until "the dock auto-hides away from the pointer" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getAutoHidden) == 'true' ]]"
wait_until "the auto-hide edge target remains available" 10 layer_on_screen one-bit-bureau-dock-edge
screenshot "success-one-bit-bureau-09-dock-auto-hidden"
move_pointer_to $((monitor_width / 2)) $((monitor_height - 1)) "the pointer reaches the dock reveal edge"
wait_until "the dock reveals from its edge target" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getAutoHidden) == 'false' ]]"
screenshot "success-one-bit-bureau-10-dock-auto-hide-revealed"
omarchy-shell regionallyfamous.one-bit-bureau.dock setAutoHide false >/dev/null

omarchy-shell regionallyfamous.one-bit-bureau.dock altTabNext >/dev/null
wait_until "One-Bit Bureau's app switcher opens" 10 layer_on_screen one-bit-bureau-dock-alt-tab
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock getAltTabActive) == "true" ]] ||
  fail "the dock reports its app switcher active"
wtype -k Right
sleep 1
screenshot "success-one-bit-bureau-11-app-switcher-keyboard"
wtype -k Escape
wait_until "Escape cancels One-Bit Bureau's app switcher" 10 layer_absent one-bit-bureau-dock-alt-tab

omarchy-shell shell summon "$PLUGIN_ID" '{}' >/dev/null
wait_until "One-Bit Bureau overview opens" 20 layer_on_screen one-bit-bureau-window-overview
wait_until "One-Bit Bureau overview instructions paint" 20 screen_contains "navigate"
sleep 2
screenshot "success-one-bit-bureau-12-overview"

omarchy-shell shell hide "$PLUGIN_ID" >/dev/null
wait_until "One-Bit Bureau overview layer closes" 20 layer_absent one-bit-bureau-window-overview
wait_until "One-Bit Bureau overview pixels clear" 10 screen_lacks "navigate"

omarchy-shell shell summon omarchy.menu '{"menu":"root"}' >/dev/null
wait_until "the One-Bit Bureau themed Omarchy menu opens" 15 layer_on_screen omarchy-menu
sleep 1
screenshot "success-one-bit-bureau-13-omarchy-menu"
wtype -k Escape
wait_until "Escape closes the Omarchy menu" 10 layer_absent omarchy-menu

setsid -f foot --app-id=one-bit-bureau-qa-ansi --title="One-Bit Bureau ANSI" bash -lc \
  'printf "\033[1;37;40m  ONE-BIT BUREAU ANSI  \033[0m\n"; for c in 30 31 32 33 34 35 36 37; do printf "\033[${c}m██ COLOR ${c} ██\033[0m  "; done; printf "\n"; sleep 60' \
  >/dev/null 2>&1
wait_until "the ANSI palette proof opens" 20 window_present '^one-bit-bureau-qa-ansi$'
sleep 2
screenshot "success-one-bit-bureau-14-terminal-ansi"

omarchy-notification-wait 10 || fail "the Omarchy notification server is ready"
omarchy-notification-send -u normal "One-Bit Bureau" "Opaque paper notification proof" -t 30000 >/dev/null
wait_until "the One-Bit Bureau notification appears" 15 screen_contains "Opaque paper"
screenshot "success-one-bit-bureau-15-notification"
omarchy-shell notifications dismissAll >/dev/null 2>&1 || true

[[ $(omarchy-shell lock preview) == "ok" ]] || fail "the Omarchy lock preview opens"
wait_until "the One-Bit Bureau lock preview is visible" 15 layer_on_screen omarchy-lock-preview
screenshot "success-one-bit-bureau-16-lock-preview"
omarchy-shell lock hidePreview >/dev/null
wait_until "the lock preview closes" 10 layer_absent omarchy-lock-preview

# A real session lock/unlock injects credentials and belongs to Omarchy's
# host-global graphical suite. The safe lock preview above proves this theme's
# lock surface without risking a stranded disposable guest.

cp "$FIXTURE/test/stubborn-state-helper.py" "$PLUGIN_DIR/components/dock/scripts/one-bit-bureau-state"
stubborn_pid_file="$HOME/.config/omarchy/one-bit-bureau/stubborn-state-helper.pid"
for _ in {1..100}; do
  [[ -s $stubborn_pid_file ]] && break
  sleep 0.02
done
[[ -s $stubborn_pid_file ]] || fail "One-Bit Bureau starts the active-unload containment fixture"
stubborn_pid=$(<"$stubborn_pid_file")
omarchy plugin disable "$PLUGIN_ID" >/dev/null
wait_until "One-Bit Bureau dock unloads" 20 layer_absent one-bit-bureau-dock
wait_until "One-Bit Bureau desktop service unloads" 20 layer_absent one-bit-bureau-desktop
wait_until "One-Bit Bureau hot corner unloads" 20 layer_absent one-bit-bureau-overview-hot-corner
wait_until "One-Bit Bureau reaps an active TERM-ignoring helper on unload" 10 \
  bash -c "! kill -0 '$stubborn_pid' 2>/dev/null"
if pgrep -f "one-bit-bureau-run.*$PLUGIN_DIR" >/dev/null 2>&1; then
  fail "One-Bit Bureau leaves no helper controller behind after unload"
fi
pass "One-Bit Bureau contains and reaps active helpers on unload"
hyprctl -j binds | jq -e 'all(.[]; ((.command // "") + " " + (.arg // "")) | contains("regionallyfamous.one-bit-bureau.dock") | not)' >/dev/null || fail "One-Bit Bureau leaves no dead global app-switcher bindings"
pass "One-Bit Bureau leaves global app-switcher bindings untouched"

close_windows '^one-bit-bureau-qa-' || true
if [[ -n $ORIGINAL_THEME ]]; then
  omarchy theme set "$ORIGINAL_THEME" >/dev/null
fi
rm -rf "$PLUGIN_DIR"
rm -rf "$THEME_TARGET"
omarchy-shell shell rescanPlugins >/dev/null
wait_until "the local fixture checkout is absent" 15 public_plugin_absent
[[ ! -e $PLUGIN_DIR && ! -e $THEME_TARGET ]] || fail "the local fixture install is fully cleaned"
pass "the local fixture install is fully cleaned before public lifecycle testing"
screenshot "success-one-bit-bureau-17-local-fixture-removed"

# Exact public lifecycle. This intentionally uses GitHub rather than the
# staged fixture. Comparing the test file's digest makes the run fail until
# public main contains the exact acceptance code being executed.
mkdir -p "$BUREAU_CONFIG"
printf 'preserve One-Bit Bureau user state\n' >"$BUREAU_CONFIG/lifecycle-user-data.txt"
public_lifecycle_active=true
omarchy plugin add "$PUBLIC_REPO_URL" --yes
[[ -d $PLUGIN_DIR/.git ]] || fail "the public plugin install is Git-managed"
wait_until "the public plugin is installed disabled for review" 15 \
  bash -c "omarchy plugin list --json | jq -e --arg id '$PLUGIN_ID' 'any(.[]; .id == \$id and .enabled == false)'"
public_acceptance_hash=$(sha256sum "$PLUGIN_DIR/test/omarchy-acceptance.sh" | awk '{print $1}')
[[ $public_acceptance_hash == "$fixture_acceptance_hash" ]] ||
  fail "public main contains the exact acceptance test under execution"
pass "public main contains the exact acceptance test under execution"

bash "$PLUGIN_DIR/setup" --adopt-plugin --yes
wait_until "the public One-Bit Bureau plugin activates" 30 \
  bash -c "omarchy plugin list --json | jq -e --arg id '$PLUGIN_ID' 'any(.[]; .id == \$id and .enabled == true)'"
wait_until "the public One-Bit Bureau dock mounts" 20 layer_on_screen one-bit-bureau-dock
[[ -f $STATE_FILE && ! -L $STATE_FILE ]] || fail "public setup records source ownership"
PUBLIC_SOURCE_ID=$(jq -er '.installed.themeSourceId' "$STATE_FILE")
PUBLIC_SOURCE_PATH="$THEME_SOURCES_DIR/$PUBLIC_SOURCE_ID"
[[ -d $PUBLIC_SOURCE_PATH/.git && ! -L $PUBLIC_SOURCE_PATH ]] ||
  fail "public setup creates a safe theme-source checkout"
[[ -L $THEME_TARGET ]] || fail "public setup installs the theme as a source-owned symlink"
[[ $(realpath "$THEME_TARGET") == "$(realpath "$PUBLIC_SOURCE_PATH/themes/$THEME_NAME")" ]] ||
  fail "the installed theme link resolves inside its recorded source"
assert_public_commit_alignment || fail "the public plugin and theme source align with public main"
pass "the public plugin, theme source, ownership record, and main branch align"
[[ -x $COMMAND_TARGET && -d $FONT_TARGET ]] || fail "public setup installs the command and bundled fonts"
screenshot "success-one-bit-bureau-18-public-install"

"$COMMAND_TARGET" motion reduce
wait_until "the One-Bit Bureau command enables reduced motion in the dock" 15 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getReducedMotion) == 'true' ]]"
wait_until "the One-Bit Bureau command enables reduced motion in the overview" 15 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.overview getReducedMotion) == 'true' ]]"
[[ $("$COMMAND_TARGET" motion status) == "reduced" ]] || fail "the One-Bit Bureau command reports reduced motion"
omarchy-shell shell summon "$PLUGIN_ID" '{}' >/dev/null
wait_until "the reduced-motion overview opens" 15 layer_on_screen one-bit-bureau-window-overview
screenshot "success-one-bit-bureau-19-reduced-motion-overview"
omarchy-shell shell hide "$PLUGIN_ID" >/dev/null
wait_until "the reduced-motion overview closes" 10 layer_absent one-bit-bureau-window-overview
"$COMMAND_TARGET" motion full
wait_until "the One-Bit Bureau command restores full motion" 15 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getReducedMotion) == 'false' && \$(omarchy-shell regionallyfamous.one-bit-bureau.overview getReducedMotion) == 'false' ]]"
[[ $("$COMMAND_TARGET" motion status) == "full" ]] || fail "the One-Bit Bureau command reports full motion"
pass "One-Bit Bureau reduced-motion control is live across dock and overview"

"$COMMAND_TARGET" update --yes
[[ $(sha256sum "$PLUGIN_DIR/test/omarchy-acceptance.sh" | awk '{print $1}') == "$fixture_acceptance_hash" ]] ||
  fail "the public update retains the exact tested acceptance code"
assert_public_commit_alignment || fail "the public update keeps plugin and theme commits aligned"
pass "the public update command keeps plugin and theme source aligned"

public_theme_source_state="$THEME_SOURCE_STATE_DIR/$PUBLIC_SOURCE_ID/installed/$THEME_NAME"
"$COMMAND_TARGET" remove
public_lifecycle_active=false
wait_until "the public plugin is removed" 20 public_plugin_absent
[[ ! -e $PLUGIN_DIR && ! -e $THEME_TARGET && ! -e $STATE_FILE ]] ||
  fail "public removal clears plugin, theme link, and ownership state"
[[ ! -e $FONT_TARGET && ! -e $COMMAND_TARGET ]] ||
  fail "public removal clears owned fonts and command"
[[ ! -e $public_theme_source_state ]] || fail "public removal detaches the theme from its source"
[[ -f $BUREAU_CONFIG/lifecycle-user-data.txt && -f $HOME/Desktop/ONE-BIT-BUREAU-QA.txt && -f $HOME/Desktop/One-Bit\ Bureau\ Photo.png ]] ||
  fail "public removal preserves One-Bit Bureau configuration and Desktop data"
[[ $(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true) == "$ORIGINAL_THEME" ]] ||
  fail "public removal restores the prior theme"
[[ $(jq -r '.bar.position // "top"' "$HOME/.config/omarchy/shell.json") == "$ORIGINAL_BAR_POSITION" ]] ||
  fail "public removal restores the prior bar position"
[[ $(jq -r '.bar.transparent // false' "$HOME/.config/omarchy/shell.json") == "$ORIGINAL_BAR_TRANSPARENT" ]] ||
  fail "public removal restores the prior bar transparency"
assert_branding_restored || fail "public removal restores the prior branding exactly"
pass "the exact public add, adopt, update, and remove lifecycle restores owned state and preserves user data"
screenshot "success-one-bit-bureau-20-public-removal-rollback"

pass "One-Bit Bureau runtime acceptance passed"
