#!/bin/bash

# omarchy-test-lab:requires=pointer
# omarchy-test-lab:timeout=900
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
QA_APP_ID="one-bit-bureau-qa-unmatched"
QA_DESKTOP_ENTRY="$HOME/.local/share/applications/$QA_APP_ID.desktop"
QA_NATIVE_ICON="$HOME/.local/share/icons/hicolor/64x64/apps/$QA_APP_ID.png"
PUBLIC_REPO_URL="https://github.com/RegionallyFamous/one-bit-bureau.git"
PUBLIC_INSTALL_URL="https://bureau.regionallyfamous.com/install"
THEME_SOURCES_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy/theme-sources"
THEME_SOURCE_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/theme-sources"
GTK3_SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini"
APP_CHROME_THEME="${XDG_DATA_HOME:-$HOME/.local/share}/themes/One-Bit-Bureau-GTK3"
APP_CHROME_STATE="$STATE_DIR/app-chrome-state.json"
APP_CHROME_BACKUP="$STATE_DIR/backups/app-chrome-settings.ini"
USER_DIRS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
ORIGINAL_THEME=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)
ORIGINAL_BAR_POSITION=$(jq -r '.bar.position // "top"' "$HOME/.config/omarchy/shell.json" 2>/dev/null || echo top)
ORIGINAL_BAR_TRANSPARENT=$(jq -r '.bar.transparent // false' "$HOME/.config/omarchy/shell.json" 2>/dev/null || echo false)
SHOWCASE_ROOT=$(mktemp -d /tmp/one-bit-bureau-showcase.XXXXXX)
PUBLIC_INSTALL_LOG="$SHOWCASE_ROOT/public-install.typescript"
SHOWCASE_DESKTOP_STASH="$SHOWCASE_ROOT/original-desktop"
SHOWCASE_DESKTOP_RETIRED="$SHOWCASE_ROOT/showcase-desktop"
SHOWCASE_FILES="$SHOWCASE_ROOT/Bureau"
SHOWCASE_BROWSER_PROFILE="$SHOWCASE_ROOT/chromium-profile"
SHOWCASE_LIBREOFFICE_PROFILE="$SHOWCASE_ROOT/libreoffice-profile"
ORIGINAL_NAUTILUS_VIEW=""
showcase_nautilus_view_changed=false
showcase_active=false
trash_fixture_active=false
operation_fixture_active=false
QMLLINT_BIN=$(command -v qmllint || true)
: "${QMLLINT_BIN:=/usr/lib/qt6/bin/qmllint}"

BASELINE_DIR=$(mktemp -d "$ARTIFACTS/one-bit-bureau-baseline.XXXXXX")
ORIGINAL_ABOUT_PRESENT=false
ORIGINAL_SCREENSAVER_PRESENT=false
ORIGINAL_GTK3_SETTINGS_PRESENT=false
ORIGINAL_APP_CHROME_THEME_PRESENT=false
ORIGINAL_USER_DIRS_PRESENT=false
if [[ -f $HOME/.config/omarchy/branding/about.txt ]]; then
  ORIGINAL_ABOUT_PRESENT=true
  cp -- "$HOME/.config/omarchy/branding/about.txt" "$BASELINE_DIR/about.txt"
fi
if [[ -f $HOME/.config/omarchy/branding/screensaver.txt ]]; then
  ORIGINAL_SCREENSAVER_PRESENT=true
  cp -- "$HOME/.config/omarchy/branding/screensaver.txt" "$BASELINE_DIR/screensaver.txt"
fi
if [[ -f $GTK3_SETTINGS && ! -L $GTK3_SETTINGS ]]; then
  ORIGINAL_GTK3_SETTINGS_PRESENT=true
  cp -- "$GTK3_SETTINGS" "$BASELINE_DIR/gtk3-settings.ini"
fi
if [[ -d $APP_CHROME_THEME && ! -L $APP_CHROME_THEME ]]; then
  ORIGINAL_APP_CHROME_THEME_PRESENT=true
  cp -a -- "$APP_CHROME_THEME" "$BASELINE_DIR/app-chrome-theme"
fi
if [[ -f $USER_DIRS_FILE && ! -L $USER_DIRS_FILE ]]; then
  ORIGINAL_USER_DIRS_PRESENT=true
  cp -- "$USER_DIRS_FILE" "$BASELINE_DIR/user-dirs.dirs"
fi

PUBLIC_SOURCE_ID=""
PUBLIC_SOURCE_PATH=""
PUBLIC_THEME_MODE=""
public_lifecycle_active=false

screen_lacks() {
  ! screen_contains "$1"
}

theme_name_is() {
  grep -Fxq -- "$1" "$HOME/.local/state/omarchy/current/theme.name"
}

bar_position_is() {
  [[ $(jq -r '.bar.position // "top"' "$HOME/.config/omarchy/shell.json") == "$1" ]]
}

bar_geometry_is() {
  local wanted="$1"

  hyprctl -j layers | jq -e --arg wanted "$wanted" '
    [.. | objects | select(.namespace? == "omarchy-bar")][0] as $bar
    | $bar != null and
      (if $wanted == "vertical" then $bar.w < $bar.h
       elif $wanted == "horizontal" then $bar.w > $bar.h
       elif $wanted == "top" then $bar.w > $bar.h and $bar.y == 0
       else false end)
  ' >/dev/null
}

one_bit_hypr_geometry_is_active() {
  hypr_option_is general.gaps_in 4 &&
    hypr_option_is general.gaps_out 8 &&
    hypr_option_is general.border_size 2 &&
    hypr_option_is decoration.rounding 0 &&
    hypr_option_is decoration.active_opacity 1 &&
    hypr_option_is decoration.inactive_opacity 1 &&
    hypr_option_is decoration.shadow.enabled 0 &&
    hypr_option_is decoration.blur.enabled 0
}

hypr_option_is() {
  local option="$1"
  local wanted="$2"

  hyprctl -j getoption "$option" | jq -e --arg wanted "$wanted" '
    if .int != null then
      (.int | tostring) == $wanted
    elif .float != null then
      (.float | tonumber) == ($wanted | tonumber)
    elif .custom != null then
      [.custom | scan("-?[0-9]+(?:[.][0-9]+)?")] as $values
      | ($values | length) > 0 and all($values[]; (tonumber) == ($wanted | tonumber))
    else
      false
    end
  ' >/dev/null
}

capture_hypr_geometry() {
  jq -n \
    --argjson gapsIn "$(hyprctl -j getoption general.gaps_in)" \
    --argjson gapsOut "$(hyprctl -j getoption general.gaps_out)" \
    --argjson borderSize "$(hyprctl -j getoption general.border_size)" \
    --argjson rounding "$(hyprctl -j getoption decoration.rounding)" \
    --argjson activeOpacity "$(hyprctl -j getoption decoration.active_opacity)" \
    --argjson inactiveOpacity "$(hyprctl -j getoption decoration.inactive_opacity)" \
    --argjson shadow "$(hyprctl -j getoption decoration.shadow.enabled)" \
    --argjson blur "$(hyprctl -j getoption decoration.blur.enabled)" \
    '{gapsIn:$gapsIn,gapsOut:$gapsOut,borderSize:$borderSize,rounding:$rounding,activeOpacity:$activeOpacity,inactiveOpacity:$inactiveOpacity,shadow:$shadow,blur:$blur}'
}

client_is_tiled() {
  hyprctl -j clients | jq -e --arg address "$1" \
    'any(.[]; .address == $address and .floating == false and (.fullscreenClient // .fullscreen // 0) == 0)' >/dev/null
}

client_is_floating() {
  hyprctl -j clients | jq -e --arg address "$1" \
    'any(.[]; .address == $address and .floating == true and (.size | type == "array" and .[0] > 0 and .[1] > 0))' >/dev/null
}

client_is_fullscreen_active() {
  hyprctl -j activewindow | jq -e --arg address "$1" \
    '.address == $address and ((.fullscreenClient // .fullscreen // 0) == 2)' >/dev/null
}

path_fingerprint() {
  local path entry relative

  for path in "$@"; do
    if [[ -L $path ]]; then
      printf 'link\t%s\t%s\n' "$path" "$(readlink -- "$path")"
    elif [[ -f $path ]]; then
      printf 'file\t%s\t%s\n' "$path" "$(sha256sum "$path" | awk '{print $1}')"
    elif [[ -d $path ]]; then
      printf 'dir\t%s\n' "$path"
      while IFS= read -r -d '' entry; do
        relative=${entry#"$path"/}
        if [[ -L $entry ]]; then
          printf 'link\t%s\t%s\n' "$relative" "$(readlink -- "$entry")"
        elif [[ -f $entry ]]; then
          printf 'file\t%s\t%s\n' "$relative" "$(sha256sum "$entry" | awk '{print $1}')"
        elif [[ -d $entry ]]; then
          printf 'dir\t%s\n' "$relative"
        else
          printf 'other\t%s\n' "$relative"
        fi
      done < <(find -P "$path" -mindepth 1 -print0 | sort -z)
    else
      printf 'absent\t%s\n' "$path"
    fi
  done | sha256sum | awk '{print $1}'
}

restore_app_chrome_baseline() {
  if [[ $ORIGINAL_GTK3_SETTINGS_PRESENT == true ]]; then
    mkdir -p "$(dirname "$GTK3_SETTINGS")"
    cp -- "$BASELINE_DIR/gtk3-settings.ini" "$GTK3_SETTINGS"
  else
    rm -f -- "$GTK3_SETTINGS"
  fi

  if [[ -e $APP_CHROME_THEME || -L $APP_CHROME_THEME ]]; then
    rm -rf -- "$APP_CHROME_THEME"
  fi
  if [[ $ORIGINAL_APP_CHROME_THEME_PRESENT == true ]]; then
    mkdir -p "$(dirname "$APP_CHROME_THEME")"
    cp -a -- "$BASELINE_DIR/app-chrome-theme" "$APP_CHROME_THEME"
  fi
  rm -f -- "$APP_CHROME_STATE" "$APP_CHROME_BACKUP"
}

restore_user_dirs_baseline() {
  if [[ $ORIGINAL_USER_DIRS_PRESENT == true ]]; then
    mkdir -p "$(dirname "$USER_DIRS_FILE")"
    cp -- "$BASELINE_DIR/user-dirs.dirs" "$USER_DIRS_FILE"
  else
    rm -f -- "$USER_DIRS_FILE"
  fi
}

configure_test_desktop() {
  local temporary

  [[ ! -L $USER_DIRS_FILE ]] || fail "the disposable guest exposes a regular XDG user-dirs configuration"
  mkdir -p "$(dirname "$USER_DIRS_FILE")"
  temporary=$(mktemp "$(dirname "$USER_DIRS_FILE")/user-dirs-test.XXXXXX")
  if [[ -f $USER_DIRS_FILE ]]; then
    grep -v '^XDG_DESKTOP_DIR=' "$USER_DIRS_FILE" >"$temporary" || true
  fi
  printf 'XDG_DESKTOP_DIR="$HOME/Desktop"\n' >>"$temporary"
  mv -- "$temporary" "$USER_DIRS_FILE"
}

icon_manager_has_terminal() {
  screen_contains "Foot" || screen_contains "Terminal"
}

notification_has_proof() {
  local file

  for file in "$HOME/.local/state/omarchy/notifications"/*.json; do
    [[ -f $file ]] || continue
    jq -e \
      '.summary == "One-Bit Bureau" and .body == "Opaque paper notification proof"' \
      "$file" >/dev/null 2>&1 && return 0
  done
  return 1
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
  local current_x current_y delta_x delta_y step_x step_y attempt

  command -v ydotool >/dev/null 2>&1 || fail "pointer automation is available"
  for (( attempt = 0; attempt < 20; attempt++ )); do
    if pointer_is_near "$target_x" "$target_y"; then
      pass "$description"
      return 0
    fi
    current_x=$(hyprctl -j cursorpos | jq -er '.x | round')
    current_y=$(hyprctl -j cursorpos | jq -er '.y | round')
    delta_x=$((target_x - current_x))
    delta_y=$((target_y - current_y))
    # Stream bounded relative events. Large one-shot REL_X/REL_Y values can be
    # clipped by the guest's virtual pointer path, especially after a drag has
    # ended in a screen corner.
    step_x=$((delta_x > 96 ? 96 : delta_x < -96 ? -96 : delta_x))
    step_y=$((delta_y > 96 ? 96 : delta_y < -96 ? -96 : delta_y))
    ydotool mousemove -- "$step_x" "$step_y" >/dev/null || fail "$description"
    sleep 0.1
  done
  fail "$description"
}

drag_pointer_to() {
  local target_x="$1"
  local target_y="$2"
  local description="$3"
  local current_x current_y delta_x delta_y step_x step_y remaining

  # Feed the QML drag handler a short stream of motion events. A single large
  # synthetic jump can move the compositor cursor without giving MouseArea a
  # useful intermediate position at which to cross its drag threshold.
  for (( remaining = 12; remaining > 0; remaining-- )); do
    current_x=$(hyprctl -j cursorpos | jq -er '.x | round')
    current_y=$(hyprctl -j cursorpos | jq -er '.y | round')
    delta_x=$((target_x - current_x))
    delta_y=$((target_y - current_y))
    step_x=$((delta_x / remaining))
    step_y=$((delta_y / remaining))
    if (( step_x == 0 && delta_x != 0 )); then
      step_x=$((delta_x > 0 ? 1 : -1))
    fi
    if (( step_y == 0 && delta_y != 0 )); then
      step_y=$((delta_y > 0 ? 1 : -1))
    fi
    ydotool mousemove -- "$step_x" "$step_y" >/dev/null || fail "$description"
    sleep 0.025
  done
  move_pointer_to "$target_x" "$target_y" "$description"
}

focus_empty_desktop() {
  local target_x target_y
  target_x=$(hyprctl -j monitors | jq -er '.[0] | (.x + (.width / .scale) / 2) | floor')
  target_y=$(hyprctl -j monitors | jq -er '.[0] | (.y + (.height / .scale) * 0.55) | floor')
  move_pointer_to "$target_x" "$target_y" "the pointer reaches empty desktop space"
  ydotool click 0xC0 >/dev/null || fail "the virtual pointer focuses the desktop"
  sleep 0.3
}

open_desk_menu() {
  omarchy-shell regionallyfamous.one-bit-bureau.desktop closeDeskMenu >/dev/null 2>&1 || true
  [[ $(omarchy-shell regionallyfamous.one-bit-bureau.desktop openDeskMenu "$monitor_name") == "true" ]] ||
    fail "the top-bar Desk command opens its desktop menu"
  wait_until "the Desk menu opens on its invoking output" 10 \
    bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.desktop getDeskMenuOpen) == 'true' && \$(omarchy-shell regionallyfamous.one-bit-bureau.desktop getDeskMenuScreen) == '$monitor_name' ]]"
}

move_desk_menu_to() {
  local wanted="$1"
  local current attempt

  for (( attempt = 0; attempt < 16; attempt++ )); do
    current=$(omarchy-shell regionallyfamous.one-bit-bureau.desktop getDeskMenuCurrentAction)
    if [[ $current == "$wanted" ]]; then
      return 0
    fi
    wtype -k Down
  done
  fail "the Desk menu keyboard cursor reaches $wanted"
}

quick_look_window_present() {
  hyprctl -j clients | jq -e '
    any(.[];
      ((.class // "") | ascii_downcase | test("nautiluspreviewer|sushi")) or
      ((.initialClass // "") | ascii_downcase | test("nautiluspreviewer|sushi"))
    )
  ' >/dev/null
}

quick_look_window_absent() {
  ! quick_look_window_present
}

quick_look_window_focused() {
  hyprctl -j activewindow | jq -e '
    ((.class // "") | ascii_downcase | test("nautiluspreviewer|sushi")) or
    ((.initialClass // "") | ascii_downcase | test("nautiluspreviewer|sushi"))
  ' >/dev/null
}

close_external_quick_look() {
  # Sushi is a D-Bus-activated GTK surface outside Quickshell. Inject Escape
  # through the VM's virtual input device so this exercises the same path as a
  # physical keyboard instead of wtype's separate Wayland virtual-keyboard
  # client, which GTK may decline even while the previewer owns focus.
  ydotool key 1:1 1:0 >/dev/null
}

operation_progress_started() {
  local progress processed total
  progress=$(omarchy-shell regionallyfamous.one-bit-bureau.desktop getOperationProgress 2>/dev/null || true)
  IFS=/ read -r processed total <<<"$progress"
  [[ $processed =~ ^[0-9]+$ && $total =~ ^[0-9]+$ ]] && (( processed > 0 && processed < total ))
}

operation_message_is() {
  local wanted="$1"
  [[ $(omarchy-shell regionallyfamous.one-bit-bureau.desktop getOperationMessage 2>/dev/null || true) == "$wanted" ]]
}

desktop_layout_item_is_not_at() {
  local item_id="$1"
  local x="$2"
  local y="$3"
  jq -e --arg screen "$monitor_name" --arg id "$item_id" \
    --argjson x "$x" --argjson y "$y" \
    '.[$screen][$id] != {x: $x, y: $y}' \
    "$BUREAU_CONFIG/desktop-icon-positions.json" >/dev/null
}

desktop_layout_differs_from() {
  local previous="$1"
  local current
  current=$(jq -cS --arg screen "$monitor_name" '.[$screen]' \
    "$BUREAU_CONFIG/desktop-icon-positions.json")
  [[ $current != "$previous" ]]
}

move_window_with_live_identity() {
  local address="$1"
  local workspace_id="$2"
  local client pid initial_class initial_title

  client=$(hyprctl -j clients | jq -cer --arg address "$address" \
    'first(.[] | select(.address == $address))') || return 66
  pid=$(jq -er '.pid' <<<"$client") || return 66
  initial_class=$(jq -er '.initialClass // ""' <<<"$client") || return 66
  initial_title=$(jq -er '.initialTitle // ""' <<<"$client") || return 66
  bash "$PLUGIN_DIR/components/overview/move-window-to-workspace" \
    "$address" "$workspace_id" "$pid" "$monitor_name" \
    "$initial_class" "$initial_title"
}

select_desktop_item_by_id() {
  local item_id="$1"
  local index tabs i

  index=$(omarchy-shell regionallyfamous.one-bit-bureau.desktop getVisualIndex "$item_id" "$monitor_name")
  [[ $index =~ ^[0-9]+$ ]] || fail "the desktop exposes a visual position for $item_id"
  tabs=$((index + 1))
  focus_empty_desktop
  for (( i = 0; i < tabs; i++ )); do
    wtype -k Tab
  done
  wait_until "the desktop selects $item_id" 10 desktop_selected_id_is "$item_id"
}

desktop_selected_id_is() {
  local wanted="$1"
  [[ $(omarchy-shell regionallyfamous.one-bit-bureau.desktop getSelectedId 2>/dev/null || true) == "$wanted" ]]
}

desktop_item_center() {
  local item_id="$1"
  local record screen_name local_x local_y monitor_x monitor_y

  record=$(jq -er --arg id "$item_id" '
    to_entries[] | select(.value[$id] != null) | [.key, .value[$id].x, .value[$id].y] | @tsv
  ' "$BUREAU_CONFIG/desktop-icon-positions.json" | head -n 1)
  read -r screen_name local_x local_y <<<"$record"
  monitor_x=$(hyprctl -j monitors | jq -er --arg name "$screen_name" '.[] | select(.name == $name) | .x | floor')
  monitor_y=$(hyprctl -j monitors | jq -er --arg name "$screen_name" '.[] | select(.name == $name) | .y | floor')
  printf '%s %s\n' "$((monitor_x + local_x + 60))" "$((monitor_y + local_y + 60))"
}

decoded_pixel_hash() {
  local image="$1"
  ffmpeg -v error -i "$image" -map 0:v:0 -f md5 - 2>/dev/null | sed -n 's/^MD5=//p'
}

decoded_channel_hash() {
  local image="$1" channel="$2"
  ffmpeg -v error -i "$image" -vf "format=rgb24,extractplanes=$channel" -f md5 - 2>/dev/null | sed -n 's/^MD5=//p'
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

capture_dock_icon_inner_pixels() {
  local app_id="$1" destination="$2"
  local bounds local_x local_y width height monitor_x monitor_y crop_x crop_y

  bounds=$(omarchy-shell regionallyfamous.one-bit-bureau.dock getIconBounds "$app_id")
  IFS=, read -r local_x local_y width height <<<"$bounds"
  [[ $local_x =~ ^-?[0-9]+$ && $local_y =~ ^-?[0-9]+$ && $width =~ ^[0-9]+$ && $height =~ ^[0-9]+$ ]] ||
    fail "the unmatched app exposes bounded dock geometry"
  monitor_x=$(hyprctl -j monitors | jq -er '.[0].x | floor')
  monitor_y=$(hyprctl -j monitors | jq -er '.[0].y | floor')
  crop_x=$((monitor_x + local_x + (width - 32) / 2))
  crop_y=$((monitor_y + local_y + (height - 32) / 2))
  timeout 10 grim -g "${crop_x},${crop_y} 32x32" "$destination" 2>/dev/null ||
    fail "the unmatched app's dock pixels are captured"
}

public_plugin_absent() {
  ! omarchy plugin list --json | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id)'
}

move_directory_contents() {
  local source="$1"
  local destination="$2"
  local item

  mkdir -p "$destination"
  while IFS= read -r -d '' item; do
    mv -- "$item" "$destination/"
  done < <(find "$source" -mindepth 1 -maxdepth 1 -print0)
}

close_showcase_apps() {
  close_windows '^([cC]hromium.*|libreoffice-writer|org.gnome.Nautilus)$' || true
}

stop_showcase_processes() {
  local attempt
  local -a showcase_pids=()

  # Only processes carrying one of the two unique mktemp-backed profile paths
  # belong to this gallery. Give them a short graceful exit, then guarantee
  # they cannot hold Omarchy's later browser-theme refresh open.
  mapfile -t showcase_pids < <(
    pgrep -f -- "--user-data-dir=$SHOWCASE_BROWSER_PROFILE|UserInstallation=file://$SHOWCASE_LIBREOFFICE_PROFILE" || true
  )
  if (( ${#showcase_pids[@]} > 0 )); then
    kill -TERM -- "${showcase_pids[@]}" 2>/dev/null || true
  fi
  for (( attempt = 0; attempt < 20; attempt++ )); do
    mapfile -t showcase_pids < <(
      pgrep -f -- "--user-data-dir=$SHOWCASE_BROWSER_PROFILE|UserInstallation=file://$SHOWCASE_LIBREOFFICE_PROFILE" || true
    )
    (( ${#showcase_pids[@]} == 0 )) && return 0
    sleep 0.1
  done
  kill -KILL -- "${showcase_pids[@]}" 2>/dev/null || true
}

close_showcase_extras() {
  local address attempt

  # Fresh profiles can surface late first-run or start-center windows after
  # the requested app windows are already mapped. Remove only those exact
  # transients, then repeat so they cannot photobomb the public gallery.
  for (( attempt = 0; attempt < 3; attempt++ )); do
    while read -r address; do
      hyprctl dispatch "hl.dsp.window.close({ window = \"address:$address\" })" >/dev/null 2>&1 ||
        hyprctl dispatch closewindow "address:$address" >/dev/null 2>&1 || true
    done < <(hyprctl -j clients | jq -r '.[]
      | select(.class == "soffice" or .title == "Chromium Additional Terms of Service")
      | .address')
    sleep 1
  done
}

showcase_has_only_curated_windows() {
  hyprctl -j clients | jq -e '
    length == 4 and
    ([.[] | select((.title // "") | startswith("Bureau Field Guide"))] | length == 1) and
    ([.[] | select((.title // "") | startswith("Bureau Release Desk"))] | length == 1) and
    ([.[] | select(.class == "org.gnome.Nautilus")] | length == 1) and
    ([.[] | select(.class == "libreoffice-writer")] | length == 1)
  ' >/dev/null
}

restore_showcase_state() {
  close_showcase_extras
  close_showcase_apps
  stop_showcase_processes
  omarchy-shell shell hide "$PLUGIN_ID" >/dev/null 2>&1 || true
  omarchy-shell notifications dismissAll >/dev/null 2>&1 || true

  if [[ $showcase_nautilus_view_changed == true ]]; then
    gsettings set org.gnome.nautilus.preferences default-folder-viewer "$ORIGINAL_NAUTILUS_VIEW" >/dev/null 2>&1 || true
    showcase_nautilus_view_changed=false
  fi

  if [[ $showcase_active == true ]]; then
    omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
    sleep 1
    mkdir -p "$SHOWCASE_DESKTOP_RETIRED"
    move_directory_contents "$HOME/Desktop" "$SHOWCASE_DESKTOP_RETIRED"
    move_directory_contents "$SHOWCASE_DESKTOP_STASH" "$HOME/Desktop"

    if [[ -f $SHOWCASE_ROOT/original-dock-pinned.json ]]; then
      cp -- "$SHOWCASE_ROOT/original-dock-pinned.json" "$BUREAU_CONFIG/dock-pinned.json"
    else
      rm -f -- "$BUREAU_CONFIG/dock-pinned.json"
    fi
    if [[ -f $SHOWCASE_ROOT/original-desktop-positions.json ]]; then
      cp -- "$SHOWCASE_ROOT/original-desktop-positions.json" "$BUREAU_CONFIG/desktop-icon-positions.json"
    else
      rm -f -- "$BUREAU_CONFIG/desktop-icon-positions.json"
    fi
    showcase_active=false
    omarchy plugin enable "$PLUGIN_ID" >/dev/null 2>&1 || true
    sleep 2
  fi
}

prepare_showcase_desktop() {
  local monitor_width right_x left_x top_y second_y third_y red_hash green_hash blue_hash

  command -v chromium >/dev/null 2>&1 || fail "the showcase has Chromium from the Omarchy base install"
  command -v nautilus >/dev/null 2>&1 || fail "the showcase has Files from the Omarchy base install"
  command -v libreoffice >/dev/null 2>&1 || fail "the showcase has Writer from the Omarchy base install"
  command -v gsettings >/dev/null 2>&1 || fail "the showcase can curate the Files presentation"
  gsettings list-keys org.gnome.nautilus.preferences 2>/dev/null | grep -qx 'default-folder-viewer' ||
    fail "the showcase can select Files' restrained list presentation"
  pass "the showcase uses real applications from the Omarchy base install"

  hyprctl dispatch 'hl.dsp.focus({ workspace = "1" })' >/dev/null 2>&1 ||
    hyprctl dispatch workspace 1 >/dev/null
  wait_until "the showcase begins on Desk 1" 10 \
    bash -c "hyprctl -j activeworkspace | jq -e '.id == 1' >/dev/null"

  mkdir -p "$SHOWCASE_DESKTOP_STASH" "$SHOWCASE_DESKTOP_RETIRED" "$SHOWCASE_FILES"
  if [[ -f $BUREAU_CONFIG/dock-pinned.json ]]; then
    cp -- "$BUREAU_CONFIG/dock-pinned.json" "$SHOWCASE_ROOT/original-dock-pinned.json"
  fi
  if [[ -f $BUREAU_CONFIG/desktop-icon-positions.json ]]; then
    cp -- "$BUREAU_CONFIG/desktop-icon-positions.json" "$SHOWCASE_ROOT/original-desktop-positions.json"
  fi
  move_directory_contents "$HOME/Desktop" "$SHOWCASE_DESKTOP_STASH"
  showcase_active=true

  # Stage the gallery while the plugin is unloaded so its live persistence
  # timers cannot race the curated pin and position snapshot back to disk.
  omarchy plugin disable "$PLUGIN_ID" >/dev/null
  wait_until "the showcase unloads the functional dock" 20 layer_absent one-bit-bureau-dock
  wait_until "the showcase unloads the functional desktop" 20 layer_absent one-bit-bureau-desktop

  mkdir -p "$HOME/Desktop/Current Work" "$HOME/Desktop/Reference"
  printf 'ONE-BIT BUREAU / FIELD GUIDE\n\nInspect a file. Open the dock. Move a window to another desk.\n' >"$HOME/Desktop/Field Guide.txt"
  printf 'Release layouts and current drafts\n' >"$HOME/Desktop/Current Work/Release Desk.txt"
  printf 'Bureau manuals and visual references\n' >"$HOME/Desktop/Reference/Bureau Manual.txt"
  cp -- "$FIXTURE/docs/assets/proof-photo.png" "$HOME/Desktop/Desk Study.png"

  mkdir -p "$SHOWCASE_FILES"
  printf 'ONE-BIT BUREAU / STUDIO NOTES\n\nA calm desk, accountable windows, and reversible work.\n' >"$SHOWCASE_FILES/Studio Notes.txt"
  printf '# Release checklist\n\n- Review the desk composition\n- Account for every open window\n- Move the active draft to Desk 2\n' >"$SHOWCASE_FILES/Release Checklist.md"
  ffmpeg -y -v error -i "$FIXTURE/docs/assets/proof-photo.png" -vf format=gray "$SHOWCASE_FILES/Desk Study.png" ||
    fail "the showcase prepares a monochrome desk study for Files"
  red_hash=$(decoded_channel_hash "$SHOWCASE_FILES/Desk Study.png" r)
  green_hash=$(decoded_channel_hash "$SHOWCASE_FILES/Desk Study.png" g)
  blue_hash=$(decoded_channel_hash "$SHOWCASE_FILES/Desk Study.png" b)
  [[ $red_hash == $green_hash && $green_hash == $blue_hash ]] ||
    fail "the Files desk study contains only grayscale pixels"
  [[ $(find "$SHOWCASE_FILES" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | paste -sd '|' -) == "Desk Study.png|Release Checklist.md|Studio Notes.txt" ]] ||
    fail "the Files showcase contains only its three authored artifacts"

  ORIGINAL_NAUTILUS_VIEW=$(gsettings get org.gnome.nautilus.preferences default-folder-viewer 2>/dev/null || true)
  [[ -n $ORIGINAL_NAUTILUS_VIEW ]] || fail "the showcase records Files' original presentation"
  ORIGINAL_NAUTILUS_VIEW=${ORIGINAL_NAUTILUS_VIEW#\'}
  ORIGINAL_NAUTILUS_VIEW=${ORIGINAL_NAUTILUS_VIEW%\'}
  gsettings set org.gnome.nautilus.preferences default-folder-viewer list-view >/dev/null ||
    fail "the showcase selects Files' restrained list presentation"
  showcase_nautilus_view_changed=true

  printf '%s\n' \
    '{"version":1,"pinned":["org.gnome.Nautilus","chromium","libreoffice-writer","obsidian","foot"],"order":["org.gnome.Nautilus","chromium","libreoffice-writer","obsidian","foot"]}' \
    >"$BUREAU_CONFIG/dock-pinned.json"

  monitor_width=$(hyprctl -j monitors | jq -er '.[0] | (.width / .scale) | floor')
  right_x=$((monitor_width - 144))
  left_x=$((right_x - 120))
  top_y=54
  second_y=196
  third_y=338
  jq -n \
    --arg screen "$monitor_name" \
    --argjson rightX "$right_x" \
    --argjson leftX "$left_x" \
    --argjson topY "$top_y" \
    --argjson secondY "$second_y" \
    --argjson thirdY "$third_y" \
    '{($screen): {
      "Current Work": {x: $rightX, y: $topY},
      "Reference": {x: $rightX, y: $secondY},
      "Field Guide.txt": {x: $rightX, y: $thirdY},
      "Desk Study.png": {x: $leftX, y: $topY}
    }}' >"$BUREAU_CONFIG/desktop-icon-positions.json"

  omarchy plugin enable "$PLUGIN_ID" >/dev/null
  wait_until "the showcase reloads the curated dock" 20 layer_on_screen one-bit-bureau-dock
  wait_until "the showcase reloads the curated desktop" 20 layer_on_screen one-bit-bureau-desktop

  wait_until "the showcase desktop contains only its four curated objects" 20 \
    bash -c "python3 '$PLUGIN_DIR/components/desktop/bin/desktop-index' | jq -e '[.items[] | select(.kind != \"trash\") | .id] | sort == [\"Current Work\",\"Desk Study.png\",\"Field Guide.txt\",\"Reference\"]' >/dev/null"
  omarchy-shell regionallyfamous.one-bit-bureau.dock getDockItemIds \
    >"$ARTIFACTS/one-bit-bureau-showcase-initial-dock-ids.json"
  wait_until "the showcase dock loads five curated application icons" 20 \
    bash -c "(( \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getItemCount) == 5 ))"
  wait_until "the showcase dock renders all five curated application icons" 20 \
    bash -c "(( \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getReadyIconCount) == 5 ))"
  wait_until "the showcase dock normalizes all five authored application icons" 20 \
    bash -c "(( \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getNormalizedPackIconCount) == 5 ))"
  sleep 2
}

launch_showcase_apps() {
  local -a chromium_flags

  mkdir -p "$SHOWCASE_BROWSER_PROFILE" "$SHOWCASE_LIBREOFFICE_PROFILE"
  touch "$SHOWCASE_BROWSER_PROFILE/First Run"
  timeout 30 libreoffice \
    "-env:UserInstallation=file://$SHOWCASE_LIBREOFFICE_PROFILE" \
    --headless --convert-to odt --outdir "$SHOWCASE_ROOT" \
    "$FIXTURE/demo/showcase-notes.html" >/dev/null 2>&1 ||
    fail "Writer prepares the local showcase document"
  [[ -s $SHOWCASE_ROOT/showcase-notes.odt ]] || fail "Writer produced the showcase document"

  chromium_flags=(
    "--user-data-dir=$SHOWCASE_BROWSER_PROFILE"
    --no-first-run
    --no-default-browser-check
    --disable-background-mode
    --disable-background-networking
    --disable-component-update
    --disable-sync
    --disable-translate
    --disable-features=MediaRouter,OptimizationHints,Translate
    --password-store=basic
    --class=chromium
  )
  setsid -f chromium "${chromium_flags[@]}" --app="file://$FIXTURE/demo/site/index.html" >/dev/null 2>&1
  wait_until "the local Bureau Field Guide opens in Chromium" 30 \
    bash -c "hyprctl -j clients | jq -e 'any(.[]; ((.title // \"\") | startswith(\"Bureau Field Guide\")))' >/dev/null"
  setsid -f chromium "${chromium_flags[@]}" --app="file://$FIXTURE/demo/site/release-desk.html" >/dev/null 2>&1
  setsid -f nautilus --new-window "$SHOWCASE_FILES" >/dev/null 2>&1
  setsid -f libreoffice \
    "-env:UserInstallation=file://$SHOWCASE_LIBREOFFICE_PROFILE" \
    --writer --norestore --nodefault --nolockcheck "$SHOWCASE_ROOT/showcase-notes.odt" >/dev/null 2>&1

  wait_until "the local Bureau Release Desk opens in Chromium" 30 \
    bash -c "hyprctl -j clients | jq -e 'any(.[]; ((.title // \"\") | startswith(\"Bureau Release Desk\")))' >/dev/null"
  wait_until "the showcase opens the real Files application" 30 window_present '^org.gnome.Nautilus$'
  wait_until "the showcase opens the real Writer application" 30 window_present '^libreoffice-writer$'
  sleep 5
  close_showcase_extras
  wait_until "the showcase contains only its four curated application windows" 15 \
    showcase_has_only_curated_windows
  pass "the showcase opens Chromium, Files, and Writer with offline local content"
  omarchy-shell regionallyfamous.one-bit-bureau.dock getDockItemIds \
    >"$ARTIFACTS/one-bit-bureau-showcase-dock-ids.json"
  wait_until "the showcase keeps all real windows under the five curated app identities" 20 \
    bash -c "(( \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getItemCount) == 5 ))"
  sleep 4
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
  if [[ $PUBLIC_THEME_MODE == "source" ]]; then
    source_commit=$(git -C "$PUBLIC_SOURCE_PATH" rev-parse HEAD)
    [[ $(realpath "$THEME_TARGET") == "$(realpath "$PUBLIC_SOURCE_PATH/themes/$THEME_NAME")" ]] || return 1
  else
    source_commit="$plugin_commit"
    [[ $PUBLIC_THEME_MODE == "plugin-link" ]] || return 1
    [[ $(realpath "$THEME_TARGET") == "$(realpath "$PLUGIN_DIR/themes/$THEME_NAME")" ]] || return 1
  fi
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
  if [[ $operation_fixture_active == true ]]; then
    find "$HOME/Desktop" -mindepth 1 -maxdepth 1 -type f -name 'Operation Proof *.bin' -delete 2>/dev/null || true
    rm -rf -- "$HOME/Desktop/Operation Proof Target"
    if [[ -f $BASELINE_DIR/operation-positions.json ]]; then
      cp -- "$BASELINE_DIR/operation-positions.json" "$BUREAU_CONFIG/desktop-icon-positions.json"
    fi
  fi
  if [[ $trash_fixture_active == true ]]; then
    gio trash --empty >/dev/null 2>&1 || true
  fi
  restore_user_dirs_baseline
  restore_showcase_state
  omarchy-shell shell hide "$PLUGIN_ID" >/dev/null 2>&1 || true
  omarchy-shell lock hidePreview >/dev/null 2>&1 || true
  omarchy-shell osd close >/dev/null 2>&1 || true
  omarchy-menu close >/dev/null 2>&1 || true
  omarchy-shell shell hide omarchy.menu >/dev/null 2>&1 || true
  omarchy-shell notifications dismissAll >/dev/null 2>&1 || true
  close_windows '^one-bit-bureau-qa-' || true
  omarchy bar position "$ORIGINAL_BAR_POSITION" >/dev/null 2>&1 || true
  rm -f -- "$QA_DESKTOP_ENTRY" "$QA_NATIVE_ICON"
  if [[ $public_lifecycle_active == true && -f $STATE_FILE ]]; then
    if [[ -x $COMMAND_TARGET ]]; then
      "$COMMAND_TARGET" remove >/dev/null 2>&1 || true
    elif [[ -f $PLUGIN_DIR/uninstall ]]; then
      bash "$PLUGIN_DIR/uninstall" >/dev/null 2>&1 || true
    fi
  fi
  if [[ -n $ORIGINAL_THEME ]]; then
    timeout 30 omarchy theme set "$ORIGINAL_THEME" >/dev/null 2>&1 || true
  fi
  if [[ -d $PLUGIN_DIR ]]; then
    rm -rf "$PLUGIN_DIR"
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi
  rm -rf "$THEME_TARGET"
  restore_app_chrome_baseline
  if [[ -d $SHOWCASE_ROOT && $SHOWCASE_ROOT == /tmp/one-bit-bureau-showcase.* ]]; then
    rm -rf "$SHOWCASE_ROOT"
  fi
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
[[ ! -e $APP_CHROME_STATE && ! -L $APP_CHROME_STATE && ! -e $APP_CHROME_BACKUP && ! -L $APP_CHROME_BACKUP ]] ||
  fail "One-Bit Bureau app-chrome ownership state is absent before installation"
[[ ! -e $APP_CHROME_THEME && ! -L $APP_CHROME_THEME ]] ||
  fail "the disposable guest leaves One-Bit Bureau's opt-in GTK3 theme target unowned"
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

mkdir -p "$HOME/Desktop" "$THEMES_DIR" "$(dirname "$PLUGIN_DIR")" "$BUREAU_CONFIG"
configure_test_desktop
mkdir -p "$(dirname "$QA_DESKTOP_ENTRY")" "$(dirname "$QA_NATIVE_ICON")"
mkdir -p "$HOME/Desktop/Projects"
printf 'Welcome to One-Bit Bureau.\n' >"$HOME/Desktop/Welcome.txt"
printf 'Desk brief\n' >"$HOME/Desktop/Desk Brief.txt"
printf 'Desk notes\n' >"$HOME/Desktop/Desk Notes.txt"
cp "$FIXTURE/docs/assets/proof-photo.png" "$HOME/Desktop/One-Bit Bureau Photo.png"
cp "$FIXTURE/docs/assets/proof-photo.png" "$QA_NATIVE_ICON"
printf '%s\n' \
  '[Desktop Entry]' \
  'Type=Application' \
  'Name=Spectrum' \
  "Exec=foot --app-id=$QA_APP_ID --title=Spectra-QA" \
  "Icon=$QA_NATIVE_ICON" \
  'Terminal=false' \
  >"$QA_DESKTOP_ENTRY"
printf '%s\n' \
  '{"version":1,"pinned":["org.gnome.Nautilus","chromium","foot","one-bit-bureau-qa-unmatched"],"order":["org.gnome.Nautilus","chromium","foot","one-bit-bureau-qa-unmatched"]}' \
  >"$BUREAU_CONFIG/dock-pinned.json"
python3 "$FIXTURE/components/desktop/bin/desktop-index" | jq -e --arg photo "$HOME/Desktop/One-Bit Bureau Photo.png" '.items[] | select(.path == $photo) | .kind == "image" and .preview == $photo' >/dev/null || fail "Desktop index exposes the real photo as a safe local preview"
pass "Desktop index exposes the real photo as a safe local preview"

xdg_disabled_root=$(mktemp -d "$SHOWCASE_ROOT/xdg-disabled.XXXXXX")
mkdir -p "$xdg_disabled_root/home/.config" "$xdg_disabled_root/home/.local/share" "$xdg_disabled_root/home/.local/state"
printf 'XDG_DESKTOP_DIR="$HOME"\n' >"$xdg_disabled_root/home/.config/user-dirs.dirs"
env \
  HOME="$xdg_disabled_root/home" \
  XDG_CONFIG_HOME="$xdg_disabled_root/home/.config" \
  XDG_DATA_HOME="$xdg_disabled_root/home/.local/share" \
  XDG_STATE_HOME="$xdg_disabled_root/home/.local/state" \
  python3 "$FIXTURE/components/desktop/bin/desktop-index" \
  >"$ARTIFACTS/one-bit-bureau-xdg-desktop-disabled.json"
jq -e '
  .desktopEnabled == false and .desktopState == "disabled" and .desktop == "" and
  ([.items[] | select(.virtual != true)] | length == 0) and
  any(.items[]; .id == "virtual:trash" and .kind == "trash")
' "$ARTIFACTS/one-bit-bureau-xdg-desktop-disabled.json" >/dev/null ||
  fail "an explicitly disabled XDG Desktop stays disabled while bounded virtual nouns remain available"
[[ ! -e $xdg_disabled_root/home/Desktop ]] || fail "disabled XDG Desktop discovery never recreates ~/Desktop"
pass "XDG Desktop disablement is explicit, non-creating, and mechanically recorded"

python3 "$FIXTURE/components/desktop/bin/desktop-index" | jq -e \
  'any(.items[]; .id == "virtual:trash" and .trashState == "empty")' >/dev/null ||
  fail "the disposable guest starts with an empty Trash before the suite creates its bounded fixture"
printf 'keep target\n' >"$HOME/ONE-BIT-BUREAU-SYMLINK-TARGET.txt"
ln -s "$HOME/ONE-BIT-BUREAU-SYMLINK-TARGET.txt" "$HOME/Desktop/Symlink to keep.txt"
python3 "$FIXTURE/components/desktop/bin/desktop-index" --trash "$HOME/Desktop/Symlink to keep.txt"
trash_fixture_active=true
[[ -f $HOME/ONE-BIT-BUREAU-SYMLINK-TARGET.txt && ! -e $HOME/Desktop/Symlink\ to\ keep.txt ]] || fail "Trash removes a Desktop symlink without trashing its target"
pass "Trash preserves a Desktop symlink target"

mkdir -p "$HOME/Downloads/applications"
printf '%s\n' \
  '[Desktop Entry]' \
  'Type=Application' \
  'Name=Bureau Terminal' \
  'Exec=foot --app-id=one-bit-bureau-qa-trusted --title=Bureau-Terminal' \
  >"$HOME/Downloads/applications/bureau-terminal.desktop"
chmod +x "$HOME/Downloads/applications/bureau-terminal.desktop"
python3 "$FIXTURE/components/desktop/bin/add-to-desktop" "$HOME/Downloads/applications/bureau-terminal.desktop" >/dev/null
[[ ! -x $HOME/Desktop/Bureau\ Terminal.desktop ]] || fail "Downloaded launchers remain untrusted"
python3 "$FIXTURE/components/desktop/bin/desktop-index" | jq -e '.items[] | select(.name == "Bureau Terminal") | .trusted == false' >/dev/null || fail "Desktop index reports copied downloaded launcher as untrusted"
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
wait_until "One-Bit Bureau renders the unmatched app's native fallback" 20 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getIconReadyForApp '$QA_APP_ID') == 'true' ]]"
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock getIconGrayscale "$QA_APP_ID") == "true" ]] ||
  fail "the unmatched automatic app icon is marked for grayscale rendering"
pass "One-Bit Bureau marks an unmatched automatic app icon for grayscale rendering"
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

[[ -n $ORIGINAL_THEME ]] || fail "the guest starts with an active theme for switch-back proof"
capture_hypr_geometry >"$BASELINE_DIR/original-hypr-geometry.json"
timeout 30 omarchy theme set one-bit-bureau >/dev/null
wait_until "One-Bit Bureau is active" 30 \
  theme_name_is one-bit-bureau
sleep 2
screen_lacks "Your config has errors" || fail "One-Bit Bureau applies without a Hyprland config error"
pass "One-Bit Bureau applies without a Hyprland config error"
wait_until "One-Bit Bureau applies its square opaque Hyprland geometry" 20 \
  one_bit_hypr_geometry_is_active
omarchy-shell notifications dismissAll >/dev/null 2>&1 || true

# Exercise the native bar routes in both orientations, then restore the
# pre-suite position before the public installer records its real baseline.
omarchy bar position bottom >/dev/null
wait_until "the Bureau bar reaches the horizontal bottom edge" 20 bar_position_is bottom
wait_until "the Bureau bar renders horizontally" 20 bar_geometry_is horizontal
layer_on_screen one-bit-bureau-desktop || fail "the desktop survives horizontal bar reflow"
layer_on_screen one-bit-bureau-dock || fail "the dock survives horizontal bar reflow"
screenshot "success-one-bit-bureau-01a1-horizontal-bar"

omarchy bar position left >/dev/null
wait_until "the Bureau bar reaches the left edge" 20 bar_position_is left
wait_until "the Bureau bar reflows vertically" 20 bar_geometry_is vertical
layer_on_screen one-bit-bureau-desktop || fail "the desktop survives vertical bar reflow"
layer_on_screen one-bit-bureau-dock || fail "the dock survives vertical bar reflow"
screenshot "success-one-bit-bureau-01a2-vertical-bar"

omarchy bar position top >/dev/null
wait_until "the Bureau bar returns to the top edge" 20 bar_position_is top
wait_until "the Bureau bar returns to horizontal top geometry" 20 bar_geometry_is top
layer_on_screen one-bit-bureau-desktop || fail "the desktop survives top bar restoration"
layer_on_screen one-bit-bureau-dock || fail "the dock survives top bar restoration"
screenshot "success-one-bit-bureau-01a3-top-bar"
pass "One-Bit Bureau survives horizontal, vertical, and intended top-bar geometry"

omarchy bar position "$ORIGINAL_BAR_POSITION" >/dev/null
wait_until "the bar scene restores the user's prior position" 20 \
  bar_position_is "$ORIGINAL_BAR_POSITION"

# Switching away must restore the previous compositor geometry exactly while
# leaving ordinary plugin layers usable; switching back must reapply Bureau.
timeout 30 omarchy theme set "$ORIGINAL_THEME" >/dev/null
wait_until "the prior theme becomes active" 30 theme_name_is "$ORIGINAL_THEME"
capture_hypr_geometry >"$ARTIFACTS/one-bit-bureau-theme-away-hypr-geometry.json"
cmp -s "$BASELINE_DIR/original-hypr-geometry.json" "$ARTIFACTS/one-bit-bureau-theme-away-hypr-geometry.json" ||
  fail "switching away restores the prior Hyprland geometry exactly"
layer_on_screen one-bit-bureau-desktop || fail "the plugin desktop remains loaded across a theme switch"
layer_on_screen one-bit-bureau-dock || fail "the plugin dock remains loaded across a theme switch"
layer_on_screen omarchy-bar || fail "the Omarchy bar remains loaded across a theme switch"
screenshot "success-one-bit-bureau-01a4-theme-away"

timeout 30 omarchy theme set one-bit-bureau >/dev/null
wait_until "One-Bit Bureau becomes active again" 30 theme_name_is one-bit-bureau
wait_until "One-Bit Bureau reapplies its Hyprland geometry" 20 \
  one_bit_hypr_geometry_is_active
layer_on_screen one-bit-bureau-desktop || fail "the plugin desktop survives returning to the Bureau theme"
layer_on_screen one-bit-bureau-dock || fail "the plugin dock survives returning to the Bureau theme"
screenshot "success-one-bit-bureau-01a5-theme-back"
pass "switching away and back restores both themes without unloading the plugin"

# Two exact compositor identities prove tiled active/inactive borders,
# floating geometry, and fullscreen geometry through supported dispatchers.
geometry_class='^one-bit-bureau-qa-geometry-'
setsid -f foot --app-id=one-bit-bureau-qa-geometry-a --title="Geometry Active" bash -lc \
  'printf "\033[1;37;40m  ACTIVE BUREAU WINDOW  \033[0m\n"; sleep 120' >/dev/null 2>&1
setsid -f foot --app-id=one-bit-bureau-qa-geometry-b --title="Geometry Inactive" bash -lc \
  'printf "\033[1;30;47m  INACTIVE BUREAU WINDOW  \033[0m\n"; sleep 120' >/dev/null 2>&1
wait_until "both Bureau geometry windows open" 20 \
  bash -c "(( \$(hyprctl -j clients | jq '[.[] | select((.class // \"\") | test(\"$geometry_class\"))] | length') == 2 ))"
geometry_a=$(hyprctl -j clients | jq -er '.[] | select(.class == "one-bit-bureau-qa-geometry-a") | .address' | head -n 1)
geometry_b=$(hyprctl -j clients | jq -er '.[] | select(.class == "one-bit-bureau-qa-geometry-b") | .address' | head -n 1)
wait_until "the active proof starts tiled" 15 client_is_tiled "$geometry_a"
wait_until "the inactive proof starts tiled" 15 client_is_tiled "$geometry_b"
bash "$PLUGIN_DIR/components/dock/scripts/focus-window" "$geometry_a" >/dev/null
wait_until "the tiled proof has an exact active window" 10 \
  bash -c "hyprctl -j activewindow | jq -e --arg address '$geometry_a' '.address == \$address' >/dev/null"
screenshot "success-one-bit-bureau-01a6-tiled-active-inactive"

hyprctl dispatch "hl.dsp.window.float({ action = \"on\", window = \"address:$geometry_a\" })" >/dev/null
hyprctl dispatch "hl.dsp.window.resize({ x = 500, y = 300, window = \"address:$geometry_a\" })" >/dev/null
hyprctl dispatch "hl.dsp.window.move({ x = 80, y = 110, window = \"address:$geometry_a\" })" >/dev/null
hyprctl dispatch "hl.dsp.window.float({ action = \"on\", window = \"address:$geometry_b\" })" >/dev/null
hyprctl dispatch "hl.dsp.window.resize({ x = 500, y = 300, window = \"address:$geometry_b\" })" >/dev/null
hyprctl dispatch "hl.dsp.window.move({ x = 620, y = 300, window = \"address:$geometry_b\" })" >/dev/null
wait_until "the active proof reaches floating geometry" 15 client_is_floating "$geometry_a"
wait_until "the inactive proof reaches floating geometry" 15 client_is_floating "$geometry_b"
bash "$PLUGIN_DIR/components/dock/scripts/focus-window" "$geometry_a" >/dev/null
screenshot "success-one-bit-bureau-01a7-floating-active-inactive"

hyprctl dispatch "hl.dsp.window.float({ action = \"off\", window = \"address:$geometry_a\" })" >/dev/null
hyprctl dispatch "hl.dsp.window.float({ action = \"off\", window = \"address:$geometry_b\" })" >/dev/null
wait_until "the fullscreen proof returns to tiling" 15 client_is_tiled "$geometry_a"
bash "$PLUGIN_DIR/components/dock/scripts/focus-window" "$geometry_a" >/dev/null
omarchy-hyprland-window-tiled-fullscreen-toggle >/dev/null
wait_until "the exact active Bureau window reaches fullscreen" 15 \
  client_is_fullscreen_active "$geometry_a"
screenshot "success-one-bit-bureau-01a8-fullscreen-active"
omarchy-hyprland-window-tiled-fullscreen-toggle >/dev/null
wait_until "the fullscreen proof returns to tiling" 15 client_is_tiled "$geometry_a"
close_windows "$geometry_class"
wait_until "the Bureau geometry windows close" 15 window_absent "$geometry_class"
pass "One-Bit Bureau renders tiled, floating, fullscreen, active, and inactive window geometry"

# Record the real guest capabilities and exercise only what is present. The
# public Test Lab does not expose a supported output hotplug/reconfiguration
# API, so the suite must not turn raw compositor monitor commands into fake
# hotplug evidence.
monitors_json=$(hyprctl -j monitors)
monitor_count=$(jq 'length' <<<"$monitors_json")
monitor_name=$(jq -er '.[0].name' <<<"$monitors_json")
fractional_scale_count=$(jq '[.[] | select((.scale - (.scale | round) | fabs) > 0.001)] | length' <<<"$monitors_json")
jq -n \
  --argjson monitors "$monitors_json" \
  --argjson monitorCount "$monitor_count" \
  --argjson fractionalScaleCount "$fractional_scale_count" \
  '{
    monitors: $monitors,
    monitorCount: $monitorCount,
    multiMonitorObserved: ($monitorCount >= 2),
    fractionalScaleObserved: ($fractionalScaleCount > 0),
    supportedOutputMutationHarness: false,
    hotplugTested: false
  }' >"$ARTIFACTS/one-bit-bureau-output-capabilities.json"
(( monitor_count >= 1 )) || fail "the Test Lab exposes at least one real output"
desktop_layer_count=$(hyprctl -j layers | jq '[.. | objects | select(.namespace? == "one-bit-bureau-desktop")] | length')
(( desktop_layer_count == monitor_count )) || fail "One-Bit Bureau maps exactly one desktop layer per real guest output"
dock_screen=$(omarchy-shell regionallyfamous.one-bit-bureau.dock getScreen)
jq -e --arg screen "$dock_screen" 'any(.[]; .name == $screen)' <<<"$monitors_json" >/dev/null ||
  fail "One-Bit Bureau assigns its dock to a real guest output"
wait_until "One-Bit Bureau records one spatial owner per desktop noun" 15 \
  bash -c "jq -e '[to_entries[].value | keys[]] | sort | group_by(.) | all(length == 1)' '$BUREAU_CONFIG/desktop-icon-positions.json' >/dev/null"
if (( monitor_count >= 2 )); then
  screenshot "success-one-bit-bureau-01a-multi-monitor-ownership"
  pass "One-Bit Bureau owns every real multi-monitor desktop surface without duplicate placement records"
else
  pass "the capability artifact records that this guest cannot prove two-monitor ownership or hotplug"
fi
if (( fractional_scale_count > 0 )); then
  screenshot "success-one-bit-bureau-01b-fractional-scale"
  pass "One-Bit Bureau is visibly exercised on the guest's real fractional-scale output"
else
  pass "the capability artifact records that this guest cannot prove fractional scaling"
fi

second_wallpaper="$THEME_TARGET/backgrounds/one-bit-bureau-cleared-shift.png"
primary_wallpaper="$THEME_TARGET/backgrounds/one-bit-bureau.png"
[[ -f $second_wallpaper && -f $primary_wallpaper ]] || fail "the installed theme exposes both wallpaper-family members"
omarchy-theme-bg-set "$second_wallpaper" >/dev/null
wait_until "the second One-Bit Bureau wallpaper becomes current" 15 \
  bash -c "[[ \$(readlink -f '$HOME/.local/state/omarchy/current/background') == '$second_wallpaper' ]]"
sleep 1
screenshot "success-one-bit-bureau-01c-second-wallpaper-crop-safe"
omarchy-theme-bg-set "$primary_wallpaper" >/dev/null
wait_until "the functional proof restores the primary wallpaper" 15 \
  bash -c "[[ \$(readlink -f '$HOME/.local/state/omarchy/current/background') == '$primary_wallpaper' ]]"
pass "both crop-safe wallpaper-family members select through Omarchy's native background state"

wait_until "the virtual Trash reports the suite-created full state" 15 \
  bash -c "python3 '$PLUGIN_DIR/components/desktop/bin/desktop-index' | jq -e 'any(.items[]; .id == \"virtual:trash\" and .trashState == \"full\" and .icon == \"user-trash-full\")' >/dev/null"
select_desktop_item_by_id "virtual:trash"
screenshot "success-one-bit-bureau-01d-virtual-trash-full"
wtype -k Return
wait_until "the virtual Trash safely opens through Omarchy's Files application" 15 window_present '^org.gnome.Nautilus$'
screenshot "success-one-bit-bureau-01e-virtual-trash-open"
close_windows '^org.gnome.Nautilus$'
wait_until "the Trash proof file manager closes" 10 window_absent '^org.gnome.Nautilus$'
gio trash --empty >/dev/null
trash_fixture_active=false
wait_until "the virtual Trash reports empty after its owned fixture is removed" 15 \
  bash -c "python3 '$PLUGIN_DIR/components/desktop/bin/desktop-index' | jq -e 'any(.items[]; .id == \"virtual:trash\" and .trashState == \"empty\" and .icon == \"user-trash\")' >/dev/null"
sleep 3
select_desktop_item_by_id "virtual:trash"
screenshot "success-one-bit-bureau-01f-virtual-trash-empty"
pass "virtual Trash has truthful empty/full identity and a bounded open action"

# Record the guest's real mount capabilities. Open a real exposed volume and
# exercise a real incapable-eject refusal when available; otherwise leave a
# truthful capability artifact instead of manufacturing a removable device.
python3 "$PLUGIN_DIR/components/desktop/bin/desktop-index" | jq \
  '[.items[] | select(.kind == "volume")]' >"$ARTIFACTS/one-bit-bureau-volume-capabilities.json"
volume_count=$(jq 'length' "$ARTIFACTS/one-bit-bureau-volume-capabilities.json")
if (( volume_count > 0 )); then
  volume_id=$(jq -er '.[0].id' "$ARTIFACTS/one-bit-bureau-volume-capabilities.json")
  volume_virtual_id=$(jq -er '.[0].virtualId' "$ARTIFACTS/one-bit-bureau-volume-capabilities.json")
  volume_open_receipt=$(python3 "$PLUGIN_DIR/components/desktop/bin/desktop-index" \
    --virtual-action open --virtual-id "$volume_virtual_id")
  jq -e '.ok == true and .state == "requested" and .action == "open"' \
    <<<"$volume_open_receipt" >/dev/null || fail "a real exposed volume opens through its revalidated identity"
  wait_until "the real volume open request reaches Files" 15 window_present '^org.gnome.Nautilus$'
  select_desktop_item_by_id "$volume_id"
  screenshot "success-one-bit-bureau-01g-volume-open"
  close_windows '^org.gnome.Nautilus$'
  wait_until "the volume proof file manager closes" 10 window_absent '^org.gnome.Nautilus$'

  incapable_volume=$(jq -cer 'map(select(.canEject != true)) | first // empty' \
    "$ARTIFACTS/one-bit-bureau-volume-capabilities.json" || true)
  if [[ -n $incapable_volume ]]; then
    incapable_id=$(jq -er '.id' <<<"$incapable_volume")
    incapable_virtual_id=$(jq -er '.virtualId' <<<"$incapable_volume")
    select_desktop_item_by_id "$incapable_id"
    wtype -M shift -k F10 -m shift
    wait_until "the incapable volume keeps its disabled Eject row visible" 10 screen_contains "Eject"
    screen_contains "Unmount" || fail "the volume menu keeps its full safe-action geometry"
    screenshot "success-one-bit-bureau-01h-volume-eject-refused"
    wtype -k Escape
    if python3 "$PLUGIN_DIR/components/desktop/bin/desktop-index" \
      --virtual-action eject --virtual-id "$incapable_virtual_id" \
      >"$ARTIFACTS/one-bit-bureau-volume-eject-refusal.json"; then
      fail "an incapable volume refuses eject before dispatch"
    fi
    jq -e '.ok == false and .state == "failed" and .error.code == "unsupported_action"' \
      "$ARTIFACTS/one-bit-bureau-volume-eject-refusal.json" >/dev/null ||
      fail "the incapable volume returns its bounded eject refusal"
    python3 "$PLUGIN_DIR/components/desktop/bin/desktop-index" | jq -e --arg id "$volume_id" \
      'any(.items[]; .id == $id and .kind == "volume")' >/dev/null ||
      fail "a refused eject leaves the real mounted volume present"
  else
    pass "the capability artifact records that every exposed guest volume advertises eject"
  fi
else
  pass "the capability artifact records that the guest exposes no safe desktop volume fixture"
fi

if python3 "$PLUGIN_DIR/components/desktop/bin/desktop-index" \
  --virtual-action eject --virtual-id 'volume:00000000000000000000000000000000' \
  >"$ARTIFACTS/one-bit-bureau-stale-volume-refusal.json"; then
  fail "a stale volume identity refuses eject without dispatch"
fi
jq -e '.ok == false and .state == "failed" and .error.code == "volume_not_found"' \
  "$ARTIFACTS/one-bit-bureau-stale-volume-refusal.json" >/dev/null ||
  fail "stale volume eject returns a bounded no-target refusal"
pass "volume actions revalidate identity and refuse unsupported or stale eject targets"

[[ ! -L $USER_DIRS_FILE ]] || fail "the disposable guest exposes a regular XDG user-dirs configuration"
mkdir -p "$(dirname "$USER_DIRS_FILE")"
user_dirs_tmp=$(mktemp "$(dirname "$USER_DIRS_FILE")/user-dirs-test.XXXXXX")
if [[ -f $USER_DIRS_FILE ]]; then
  grep -v '^XDG_DESKTOP_DIR=' "$USER_DIRS_FILE" >"$user_dirs_tmp" || true
fi
printf 'XDG_DESKTOP_DIR="$HOME"\n' >>"$user_dirs_tmp"
mv -- "$user_dirs_tmp" "$USER_DIRS_FILE"
wait_until "the live desktop honors explicit XDG Desktop disablement" 15 \
  bash -c "python3 '$PLUGIN_DIR/components/desktop/bin/desktop-index' | jq -e '.desktopEnabled == false and .desktopState == \"disabled\" and ([.items[] | select(.virtual != true)] | length == 0)' >/dev/null"
wait_until "the shell renders its disabled Desktop explanation" 15 screen_contains "Desktop files are off"
open_desk_menu
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.desktop getDeskMenuCurrentAction) == "tidy" ]] ||
  fail "the disabled Desktop menu skips file-creation actions without removing their rows"
screenshot "success-one-bit-bureau-01i-xdg-desktop-disabled"
wtype -k Escape
configure_test_desktop
wait_until "restoring XDG user dirs returns the real desktop model" 20 \
  bash -c "python3 '$PLUGIN_DIR/components/desktop/bin/desktop-index' | jq -e '.desktopEnabled == true and any(.items[]; .id == \"One-Bit Bureau Photo.png\")' >/dev/null"
wait_until "the live desktop clears its disabled explanation" 20 screen_lacks "Desktop files are off"
pass "the live shell disables and restores XDG Desktop ownership without recreating user data"

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
idle_photo_red_hash=$(decoded_channel_hash "$ARTIFACTS/one-bit-bureau-photo-idle-inner.png" r)
idle_photo_green_hash=$(decoded_channel_hash "$ARTIFACTS/one-bit-bureau-photo-idle-inner.png" g)
idle_photo_blue_hash=$(decoded_channel_hash "$ARTIFACTS/one-bit-bureau-photo-idle-inner.png" b)
[[ -n $idle_photo_red_hash && $idle_photo_red_hash == "$idle_photo_green_hash" && $idle_photo_red_hash == "$idle_photo_blue_hash" ]] ||
  fail "the real photo thumbnail is not grayscale"
cmp -s "$FIXTURE/docs/assets/proof-photo.png" "$HOME/Desktop/One-Bit Bureau Photo.png" ||
  fail "the grayscale desktop preview changed the original photo file"
pass "One-Bit Bureau keeps the original photo intact behind a constant grayscale desktop preview"

wtype -M ctrl -k i -m ctrl
wait_until "the shared Inspector opens for a desktop object" 15 layer_on_screen regionallyfamous.one-bit-bureau.inspector
wait_until "the desktop Inspector paints its facts" 15 screen_contains "FACTS"
screenshot "success-one-bit-bureau-02c-desktop-inspector"
wtype -k Escape
wait_until "Escape closes the desktop Inspector" 10 layer_absent regionallyfamous.one-bit-bureau.inspector

# The top-bar entry delegates to one selection-aware Desk menu. Prove the
# stable row set first with no selection (core noun actions disabled), then
# again with one local file selected. Keeping disabled rows in place is part
# of the geometry contract; keyboard traversal must skip them, not reflow.
focus_empty_desktop
open_desk_menu
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.desktop getDeskMenuCurrentAction) == "folder" ]] ||
  fail "the Desk menu starts on its first enabled action"
desk_menu_labels=$(omarchy-shell regionallyfamous.one-bit-bureau.desktop getDeskMenuLabels)
[[ $desk_menu_labels == "New Folder|Quick Look|Get Info|Rename|Tidy Desk|Arrange By|Name|Kind|Modified|Undo Desk Layout|Move to Trash" ]] ||
  fail "the stable Desk menu keeps its complete ordered row set"
screenshot "success-one-bit-bureau-02j-desk-menu-disabled-stable"
wtype -k Escape
wait_until "Escape closes the Desk menu" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.desktop getDeskMenuOpen) == 'false' ]]"

select_desktop_item_by_id "One-Bit Bureau Photo.png"
open_desk_menu
screenshot "success-one-bit-bureau-02k-desk-menu-selection-aware"

# Activate the second stable row with the pointer. The menu is anchored at
# padLeft+12,padTop+8 on the invoking output, with 44px rows and 2px spacing.
monitor_x=$(jq -er '.[0].x | floor' <<<"$monitors_json")
monitor_y=$(jq -er '.[0].y | floor' <<<"$monitors_json")
desk_pad_top=24
desk_pad_left=24
if [[ $ORIGINAL_BAR_POSITION == "top" ]]; then
  desk_pad_top=50
elif [[ $ORIGINAL_BAR_POSITION == "left" ]]; then
  desk_pad_left=50
fi
quick_look_row_x=$((monitor_x + desk_pad_left + 12 + 100))
quick_look_row_y=$((monitor_y + desk_pad_top + 8 + 6 + 44 + 2 + 22))
move_pointer_to "$quick_look_row_x" "$quick_look_row_y" "the pointer reaches Quick Look in the Desk menu"
ydotool click 0xC0 >/dev/null
wait_until "pointer Quick Look opens GNOME Sushi" 15 quick_look_window_present
wait_until "pointer Quick Look receives keyboard focus" 10 quick_look_window_focused
screenshot "success-one-bit-bureau-02l-quick-look-pointer"
close_external_quick_look
wait_until "Escape closes pointer Quick Look" 10 quick_look_window_absent

select_desktop_item_by_id "One-Bit Bureau Photo.png"
wtype -k Space
wait_until "keyboard Quick Look opens the same GNOME Sushi surface" 15 quick_look_window_present
wait_until "keyboard Quick Look receives keyboard focus" 10 quick_look_window_focused
screenshot "success-one-bit-bureau-02m-quick-look-keyboard"
close_external_quick_look
wait_until "Escape closes keyboard Quick Look" 10 quick_look_window_absent
pass "pointer and keyboard Quick Look converge on the same real previewer"

# Rename is an item-anchored, no-overwrite transaction. Exercise success,
# collision, and cancellation through the real desktop keyboard surface.
select_desktop_item_by_id "Welcome.txt"
wtype -k F2
wait_until "F2 opens the desktop rename dialog" 10 screen_contains "Rename"
wtype -M ctrl -k a -m ctrl
wtype "Renamed Welcome.txt"
wtype -k Return
wait_until "the desktop commits a non-colliding rename" 15 \
  bash -c "[[ -f '$HOME/Desktop/Renamed Welcome.txt' && ! -e '$HOME/Desktop/Welcome.txt' ]]"
wait_until "the renamed item is reselected under its new identity" 15 \
  bash -c "python3 '$PLUGIN_DIR/components/desktop/bin/desktop-index' | jq -e '.items[] | select(.id == \"Renamed Welcome.txt\")' >/dev/null"
screenshot "success-one-bit-bureau-02n-rename-success"

select_desktop_item_by_id "Renamed Welcome.txt"
wtype -k F2
wtype -M ctrl -k a -m ctrl
wtype "Desk Brief.txt"
wtype -k Return
wait_until "a colliding rename remains in its dialog" 10 screen_contains "already exists"
[[ -f $HOME/Desktop/Renamed\ Welcome.txt && -f $HOME/Desktop/Desk\ Brief.txt ]] ||
  fail "a colliding rename preserves both source and destination"
screenshot "success-one-bit-bureau-02o-rename-collision"
wtype -k Escape
[[ -f $HOME/Desktop/Renamed\ Welcome.txt && ! -e $HOME/Desktop/Welcome.txt ]] ||
  fail "Escape cancels rename without changing the current name"
select_desktop_item_by_id "Renamed Welcome.txt"
wtype -k F2
wtype -M ctrl -k a -m ctrl
wtype "Cancelled Rename.txt"
screenshot "success-one-bit-bureau-02p-rename-cancel-ready"
wtype -k Escape
[[ -f $HOME/Desktop/Renamed\ Welcome.txt && ! -e $HOME/Desktop/Cancelled\ Rename.txt ]] ||
  fail "explicit rename cancellation leaves the filesystem unchanged"
wtype -k Escape
pass "desktop rename succeeds atomically, refuses collisions, and cancels cleanly"

# A full marquee over the real icon bounds must select the same bounded set as
# Ctrl+A. Capture while the pointer is still down so the marquee itself, not
# only its final selection, is part of the visual evidence. Use the live panel
# bounds rather than retained user layout records, which may include objects
# that are not part of this session's desktop model. The pointer gesture does
# not need keyboard focus, so do not add an unrelated empty click immediately
# before it.
marquee_bounds=$(omarchy-shell regionallyfamous.one-bit-bureau.desktop getVisualBounds "$monitor_name")
jq -e 'type == "array" and length > 0 and all(.[];
  (.id | type == "string" and length > 0 and length <= 255) and
  (.x | type == "number") and (.y | type == "number") and
  (.width | type == "number" and . > 0) and (.height | type == "number" and . > 0))' \
  <<<"$marquee_bounds" >/dev/null || fail "the desktop exposes bounded live geometry for the marquee proof"
read -r marquee_min_x marquee_min_y marquee_max_x marquee_max_y < <(jq -er '
  [([.[].x] | min),
   ([.[].y] | min),
   ([.[] | .x + .width] | max),
   ([.[] | .y + .height] | max)] | @tsv
' <<<"$marquee_bounds")
logical_width=$(jq -er '.[0] | (.width / .scale) | floor' <<<"$monitors_json")
logical_height=$(jq -er '.[0] | (.height / .scale) | floor' <<<"$monitors_json")
marquee_start_x=$((monitor_x + marquee_max_x + 12))
marquee_start_y=$((monitor_y + marquee_max_y + 12))
(( marquee_start_x < monitor_x + logical_width - 4 && marquee_start_y < monitor_y + logical_height - 4 )) ||
  fail "the deterministic Test Lab layout leaves empty space for a full marquee gesture"
marquee_end_x=$((monitor_x + marquee_min_x - 8))
marquee_end_y=$((monitor_y + marquee_min_y - 8))
layer_absent omarchy-image-selector >/dev/null ||
  fail "the wallpaper picker stays closed before the marquee gesture"
move_pointer_to "$marquee_start_x" "$marquee_start_y" "the pointer reaches empty space beyond every desktop item"
ydotool click 0x40 >/dev/null
drag_pointer_to "$marquee_end_x" "$marquee_end_y" "the pointer draws a marquee around every desktop item"
screenshot "success-one-bit-bureau-02q-marquee-active"
ydotool click 0x80 >/dev/null
marquee_selection_count=$(omarchy-shell regionallyfamous.one-bit-bureau.desktop getSelectionCount)
(( marquee_selection_count > 0 )) || fail "the pointer marquee selects real desktop items"
focus_empty_desktop
wtype -M ctrl -k a -m ctrl
ctrl_a_selection_count=$(omarchy-shell regionallyfamous.one-bit-bureau.desktop getSelectionCount)
[[ $ctrl_a_selection_count == "$marquee_selection_count" ]] ||
  fail "Ctrl+A and a full pointer marquee select the same desktop object set"
screenshot "success-one-bit-bureau-02r-ctrl-a-equivalent"
pass "marquee and Ctrl+A selection are equivalent on the real desktop model"

# Force one saved position off the deterministic grid, then prove Tidy,
# Arrange by Name, and exact one-step layout Undo through the Desk menu.
positions_tmp=$(mktemp "$BUREAU_CONFIG/positions-test.XXXXXX")
jq --arg screen "$monitor_name" '.[$screen]["Renamed Welcome.txt"] = {x: 850, y: 350}' \
  "$BUREAU_CONFIG/desktop-icon-positions.json" >"$positions_tmp"
mv -- "$positions_tmp" "$BUREAU_CONFIG/desktop-icon-positions.json"
wait_until "the desktop reloads the deliberately untidy position" 10 \
  bash -c "jq -e --arg screen '$monitor_name' '.[\$screen][\"Renamed Welcome.txt\"] == {x:850,y:350}' '$BUREAU_CONFIG/desktop-icon-positions.json' >/dev/null"
focus_empty_desktop
open_desk_menu
move_desk_menu_to "tidy"
wtype -k Return
wait_until "Tidy Desk publishes its reversible receipt" 10 operation_message_is "Tidied the Desk"
wait_until "Tidy Desk persists its replacement geometry" 10 \
  desktop_layout_item_is_not_at "Renamed Welcome.txt" 850 350
tidy_layout=$(jq -cS --arg screen "$monitor_name" '.[ $screen ]' "$BUREAU_CONFIG/desktop-icon-positions.json")
screenshot "success-one-bit-bureau-02s-tidy-desk"

focus_empty_desktop
open_desk_menu
move_desk_menu_to "arrange-name"
wtype -k Return
wait_until "Arrange by Name publishes its reversible receipt" 10 operation_message_is "Arranged the Desk by Name"
wait_until "Arrange by Name persists a distinct saved order" 10 \
  desktop_layout_differs_from "$tidy_layout"
arranged_layout=$(jq -cS --arg screen "$monitor_name" '.[ $screen ]' "$BUREAU_CONFIG/desktop-icon-positions.json")
screenshot "success-one-bit-bureau-02t-arrange-by-name"
wtype -M ctrl -k z -m ctrl
wait_until "layout Undo restores the exact prior per-screen positions" 10 \
  bash -c "[[ \$(jq -cS --arg screen '$monitor_name' '.[ \$screen ]' '$BUREAU_CONFIG/desktop-icon-positions.json') == '$tidy_layout' ]]"
wait_until "layout Undo names its completed receipt" 10 operation_message_is "Undid the last desk layout"
screenshot "success-one-bit-bureau-02u-layout-undo"
pass "Tidy, Arrange, and layout Undo operate on deterministic saved geometry"

# Return the durable fixture name so the later curated gallery and exact
# public uninstall assertions still verify the original user data contract.
select_desktop_item_by_id "Renamed Welcome.txt"
wtype -k F2
wtype -M ctrl -k a -m ctrl
wtype "Welcome.txt"
wtype -k Return
wait_until "the rename fixture returns to its durable name" 15 \
  bash -c "[[ -f '$HOME/Desktop/Welcome.txt' && ! -e '$HOME/Desktop/Renamed Welcome.txt' ]]"

for route_item in "Desk Brief.txt" "Desk Notes.txt" "Projects" "Bureau Terminal.desktop"; do
  wait_until "One-Bit Bureau saves a position for $route_item" 15 \
    bash -c "jq -e --arg id '$route_item' 'any(to_entries[]; .value[\$id] != null)' '$BUREAU_CONFIG/desktop-icon-positions.json'"
done
read -r route_alpha_x route_alpha_y < <(desktop_item_center "Desk Brief.txt")
move_pointer_to "$route_alpha_x" "$route_alpha_y" "the pointer reaches the first routing item"
ydotool click 0xC0 >/dev/null
# Use the desktop's native keyboard range selection. The Test Lab's virtual
# keyboard and pointer are separate devices, so a modifier held by wtype is
# not guaranteed to decorate a ydotool click on every compositor build.
wtype -M shift -k Down -m shift
sleep 0.5
screenshot "success-one-bit-bureau-02d-desktop-multi-selection"

read -r route_target_x route_target_y < <(desktop_item_center "Projects")
move_pointer_to "$route_alpha_x" "$route_alpha_y" "the pointer reaches the selected routing group"
ydotool click 0x40 >/dev/null
sleep 0.1
drag_pointer_to "$route_target_x" "$route_target_y" "the selected group reaches Projects"
# Capture the transient route slip immediately, then release before the
# intentionally delayed spring-open action can cover the desktop. The real
# route and its two-item cardinality are proven below through filesystem state.
screenshot "success-one-bit-bureau-02e-desktop-route-slip"
ydotool click 0x80 >/dev/null
wait_until "the desktop route moves both selected files" 20 \
  bash -c "[[ -f '$HOME/Desktop/Projects/Desk Brief.txt' && -f '$HOME/Desktop/Projects/Desk Notes.txt' && ! -e '$HOME/Desktop/Desk Brief.txt' && ! -e '$HOME/Desktop/Desk Notes.txt' ]]"
wait_until "the desktop route receipt offers Undo" 15 screen_contains "Undo"
screenshot "success-one-bit-bureau-02f-desktop-route-receipt"
wtype -M ctrl -k z -m ctrl
wait_until "Undo restores both routed files" 20 \
  bash -c "[[ -f '$HOME/Desktop/Desk Brief.txt' && -f '$HOME/Desktop/Desk Notes.txt' && ! -e '$HOME/Desktop/Projects/Desk Brief.txt' && ! -e '$HOME/Desktop/Projects/Desk Notes.txt' ]]"
# The restored filesystem state is the authoritative proof. Capture the
# eight-second completion receipt immediately instead of depending on OCR for
# one small word in a deliberately pixel-sized UI.
sleep 0.5
screenshot "success-one-bit-bureau-02g-desktop-route-undone"
pass "One-Bit Bureau routes a bounded multi-selection with a named verb, receipt, and proven Undo"

select_desktop_item_by_id "Desk Brief.txt"
read -r route_alpha_x route_alpha_y < <(desktop_item_center "Desk Brief.txt")
read -r route_reject_x route_reject_y < <(desktop_item_center "Bureau Terminal.desktop")
move_pointer_to "$route_alpha_x" "$route_alpha_y" "the pointer reaches the rejected-route source"
ydotool click 0x40 >/dev/null
sleep 0.1
drag_pointer_to "$route_reject_x" "$route_reject_y" "the selected file reaches an application launcher"
screenshot "success-one-bit-bureau-02h-desktop-route-rejected"
ydotool click 0x80 >/dev/null
wait_until "the rejected desktop route closes" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.desktop getRouteVisible) == 'false' ]]"
wait_until "the desktop records the exact rejected route" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.desktop getLastRouteValid) == 'false' && \$(omarchy-shell regionallyfamous.one-bit-bureau.desktop getLastRouteReason) == 'Applications do not accept desktop files here' ]]"
[[ -f $HOME/Desktop/Desk\ Brief.txt && -f $HOME/Desktop/Desk\ Notes.txt ]] ||
  fail "the rejected desktop route changed its sources"
wait_until "the rejected desktop route paints a local refusal receipt" 10 screen_contains "cannot be routed"
screenshot "success-one-bit-bureau-02i-desktop-route-rejection-receipt"
pass "One-Bit Bureau names and safely refuses an invalid desktop route"
focus_empty_desktop
wtype -k Escape
wait_until "the rejected route receipt dismisses before the copy proof" 10 screen_lacks "cannot be routed"

# Drive a real multi-file copy through the desktop frontend so reserve,
# running progress, cooperative Cancel, and a terminal partial receipt are all
# observed in the shell. Sparse sources keep fixture creation cheap; the
# helper still copies bytes in bounded 1 MiB chunks and checks cancellation at
# every chunk.
[[ ! -e $HOME/Desktop/Operation\ Proof\ Target ]] || fail "the operation proof target name is unowned before the test"
if find "$HOME/Desktop" -mindepth 1 -maxdepth 1 -type f -name 'Operation Proof *.bin' -print -quit | grep -q .; then
  fail "the operation proof source names are unowned before the test"
fi
cp -- "$BUREAU_CONFIG/desktop-icon-positions.json" "$BASELINE_DIR/operation-positions.json"
operation_fixture_active=true
for operation_index in $(seq -w 1 40); do
  truncate -s 67108864 "$HOME/Desktop/Operation Proof $operation_index.bin"
done
wait_until "the desktop indexes the bounded operation proof sources" 20 \
  bash -c "(( \$(python3 '$PLUGIN_DIR/components/desktop/bin/desktop-index' | jq '[.items[] | select(.id | startswith(\"Operation Proof \"))] | length') == 40 ))"
wait_until "the desktop saves geometry for the operation proof sources" 20 \
  bash -c "jq -e --arg screen '$monitor_name' '.[\$screen][\"Operation Proof 40.bin\"] != null' '$BUREAU_CONFIG/desktop-icon-positions.json' >/dev/null"
focus_empty_desktop
wtype -M ctrl -k a -m ctrl
operation_selected_count=$(omarchy-shell regionallyfamous.one-bit-bureau.desktop getSelectionCount)
(( operation_selected_count >= 32 )) || fail "the bounded copy proof selects enough real sources to expose progress"
mkdir "$HOME/Desktop/Operation Proof Target"
wait_until "the copy target appears after the source selection snapshot" 15 \
  bash -c "python3 '$PLUGIN_DIR/components/desktop/bin/desktop-index' | jq -e '.items[] | select(.id == \"Operation Proof Target\" and .kind == \"folder\")' >/dev/null"
wait_until "the desktop saves geometry for the unselected copy target" 15 \
  bash -c "jq -e --arg screen '$monitor_name' '.[\$screen][\"Operation Proof Target\"] != null' '$BUREAU_CONFIG/desktop-icon-positions.json' >/dev/null"
# Keep the new, intentionally unselected target visible without shrinking the
# bounded source set: exchange its overflow slot with one selected source's
# known on-screen slot. Selection is identity-based, so geometry changes do
# not admit the target into the snapshot being copied.
operation_visible_position=$(jq -c --arg screen "$monitor_name" \
  '.[$screen]["Operation Proof 01.bin"]' "$BUREAU_CONFIG/desktop-icon-positions.json")
operation_positions_tmp=$(mktemp "$BUREAU_CONFIG/operation-target.XXXXXX")
jq --arg screen "$monitor_name" '
  .[$screen]["Operation Proof Target"] as $target |
  .[$screen]["Operation Proof 01.bin"] as $source |
  .[$screen]["Operation Proof Target"] = $source |
  .[$screen]["Operation Proof 01.bin"] = $target
' "$BUREAU_CONFIG/desktop-icon-positions.json" >"$operation_positions_tmp"
mv -- "$operation_positions_tmp" "$BUREAU_CONFIG/desktop-icon-positions.json"
jq -e --arg screen "$monitor_name" --argjson wanted "$operation_visible_position" \
  '.[$screen]["Operation Proof Target"] == $wanted' \
  "$BUREAU_CONFIG/desktop-icon-positions.json" >/dev/null ||
  fail "the unselected copy target moves into the visible proof slot"
sleep 0.5
read -r operation_target_x operation_target_y < <(desktop_item_center "Operation Proof Target")
move_pointer_to "$operation_target_x" "$operation_target_y" "the pointer reaches the operation proof target"
ydotool click 0xC1 >/dev/null
wait_until "the unselected folder offers semantic copy routing for the selected group" 10 screen_contains "Copy Selected Here"
wtype -k Down
wtype -k Down
wtype -k Down
wtype -k Return
wait_until "the desktop copy enters a cancellable running state" 15 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.desktop getOperationBusy) == 'true' && \$(omarchy-shell regionallyfamous.one-bit-bureau.desktop getOperationCancellable) == 'true' ]]"
wait_until "the desktop copy publishes real intermediate progress" 20 operation_progress_started
screenshot "success-one-bit-bureau-02v-operation-running-progress"
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.desktop cancelOperation) == "true" ]] ||
  fail "the visible operation accepts cooperative cancellation"
screenshot "success-one-bit-bureau-02w-operation-cancelling"
wait_until "the cancelled copy reaches its terminal partial state" 30 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.desktop getOperationBusy) == 'false' && \$(omarchy-shell regionallyfamous.one-bit-bureau.desktop getOperationState) == 'partial' ]]"
wait_until "the partial operation receipt names completed and failed work" 10 screen_contains "items completed"
screenshot "success-one-bit-bureau-02x-operation-partial"
(( $(find "$HOME/Desktop/Operation Proof Target" -mindepth 1 -maxdepth 1 | wc -l) > 0 )) ||
  fail "the partial receipt corresponds to at least one completed copy"
find "$HOME/Desktop" -mindepth 1 -maxdepth 1 -type f -name 'Operation Proof *.bin' -delete
rm -rf -- "$HOME/Desktop/Operation Proof Target"
cp -- "$BASELINE_DIR/operation-positions.json" "$BUREAU_CONFIG/desktop-icon-positions.json"
operation_fixture_active=false
sleep 3
pass "desktop operations expose reservation, running progress, cooperative cancellation, and truthful partial completion"

capture_dock_icon_inner_pixels "$QA_APP_ID" "$ARTIFACTS/one-bit-bureau-unmatched-auto.png"
auto_icon_red_hash=$(decoded_channel_hash "$ARTIFACTS/one-bit-bureau-unmatched-auto.png" r)
auto_icon_green_hash=$(decoded_channel_hash "$ARTIFACTS/one-bit-bureau-unmatched-auto.png" g)
auto_icon_blue_hash=$(decoded_channel_hash "$ARTIFACTS/one-bit-bureau-unmatched-auto.png" b)
[[ -n $auto_icon_red_hash && $auto_icon_red_hash == "$auto_icon_green_hash" && $auto_icon_red_hash == "$auto_icon_blue_hash" ]] ||
  fail "the unmatched automatic app icon pixels are not grayscale"
screenshot "success-one-bit-bureau-02a-unmatched-app-automatic-grayscale"

bash "$PLUGIN_DIR/components/dock/scripts/one-bit-bureau-icon" native "$QA_APP_ID" >/dev/null
wait_until "explicit Native mode removes grayscale from the unmatched app" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getIconGrayscale '$QA_APP_ID') == 'false' ]]"
sleep 1
capture_dock_icon_inner_pixels "$QA_APP_ID" "$ARTIFACTS/one-bit-bureau-unmatched-native.png"
native_icon_red_hash=$(decoded_channel_hash "$ARTIFACTS/one-bit-bureau-unmatched-native.png" r)
native_icon_green_hash=$(decoded_channel_hash "$ARTIFACTS/one-bit-bureau-unmatched-native.png" g)
native_icon_blue_hash=$(decoded_channel_hash "$ARTIFACTS/one-bit-bureau-unmatched-native.png" b)
[[ -n $native_icon_red_hash && ($native_icon_red_hash != "$native_icon_green_hash" || $native_icon_red_hash != "$native_icon_blue_hash") ]] ||
  fail "explicit Native mode did not restore the unmatched app's color pixels"
screenshot "success-one-bit-bureau-02b-unmatched-app-explicit-native-color"

bash "$PLUGIN_DIR/components/dock/scripts/one-bit-bureau-icon" auto "$QA_APP_ID" >/dev/null
wait_until "Automatic mode restores grayscale for the unmatched app" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getIconGrayscale '$QA_APP_ID') == 'true' ]]"
pass "unmatched app icons default to grayscale and explicit Native restores color"

# Resolve a real Wayland window through the same identity layer used by the
# dock, then require focus and close actions to report observed compositor
# postconditions instead of treating dispatch success as completion.
setsid -f foot --app-id="$QA_APP_ID" --title="Spectrum Identity Proof" >/dev/null 2>&1
wait_until "the application-identity proof window opens" 20 window_present "^$QA_APP_ID$"
identity_address=$(hyprctl -j clients | jq -er --arg class "$QA_APP_ID" '.[] | select(.class == $class) | .address' | head -n 1)
identity_result=$(omarchy-shell regionallyfamous.one-bit-bureau.dock getIdentityForAddress "$identity_address")
jq -e --arg id "$QA_APP_ID" '.id == $id and .method == "exact-app-id" and .ambiguous == false' \
  <<<"$identity_result" >/dev/null || fail "the real Wayland window resolves by exact app identity"
dock_ids=$(omarchy-shell regionallyfamous.one-bit-bureau.dock getDockItemIds)
(( $(jq --arg id "$QA_APP_ID" '[.[] | select(. == $id)] | length' <<<"$dock_ids") == 1 )) ||
  fail "one application identity occupies exactly one dock noun"
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock requestFocusForApp "$QA_APP_ID") == "true" ]] ||
  fail "the dock accepts a focus request for the proven app identity"
wait_until "dock focus reports an observed compositor postcondition" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getLastActionState) == 'observed' && \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getLastActionKind) == 'focus' && \$(hyprctl -j activewindow | jq -r .address) == '$identity_address' ]]"
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock requestCloseForApp "$QA_APP_ID") == "true" ]] ||
  fail "the dock accepts a close request for the proven app identity"
wait_until "dock close reports an observed compositor postcondition" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getLastActionState) == 'observed' && \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getLastActionKind) == 'close' ]] && ! hyprctl -j clients | jq -e --arg address '$identity_address' 'any(.[]; .address == \$address)' >/dev/null"
pass "application identity stays singular and dock actions report observed postconditions"

read -r context_x context_y < <(desktop_item_center "Projects")
move_pointer_to "$context_x" "$context_y" "the pointer reaches the desktop context target"
ydotool click 0xC0 >/dev/null
wtype -M shift -k F10 -m shift
wait_until "the desktop keyboard context menu opens" 10 screen_contains "Show in Files"
screenshot "success-one-bit-bureau-03-desktop-keyboard-context-menu"
wtype -k Escape
wait_until "the desktop keyboard context menu closes" 10 screen_lacks "Show in Files"

read -r untrusted_x untrusted_y < <(desktop_item_center "Bureau Terminal.desktop")
move_pointer_to "$untrusted_x" "$untrusted_y" "the pointer reaches the untrusted launcher"
ydotool click 0xC0 >/dev/null
wtype -k Return
wait_until "the untrusted launcher confirmation opens from the keyboard" 10 screen_contains "Untrusted launcher"
screenshot "success-one-bit-bureau-04-untrusted-launcher-confirmation"
wtype -k Return
wait_until "Enter safely cancels the trust prompt" 10 screen_lacks "Untrusted launcher"
[[ ! -x $HOME/Desktop/Bureau\ Terminal.desktop ]] || fail "Enter never trusts an untrusted launcher"

wtype -k Return
wait_until "the trust prompt reopens" 10 screen_contains "Untrusted launcher"
wtype -k Tab
wtype -k Space
wait_until "keyboard trust marks the launcher executable" 10 test -x "$HOME/Desktop/Bureau Terminal.desktop"
wait_until "keyboard trust opens the launcher" 20 window_present '^one-bit-bureau-qa-trusted$'
pass "One-Bit Bureau's trust flow keeps Cancel safe and requires an explicit keyboard choice"
close_windows '^one-bit-bureau-qa-trusted$'
wait_until "the trusted-launcher proof window closes" 10 window_absent '^one-bit-bureau-qa-trusted$'

[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock openMenuFirst) == "true" ]] ||
  fail "the dock exposes its first app menu"
wait_until "the dock app menu opens" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getMenuOpen) == 'true' ]]"
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock getMenuCurrentAction) == "inspect" ]] ||
  fail "the dock menu starts on Get Info"
wtype -k Return
wait_until "the shared Inspector opens for a dock application" 15 layer_on_screen regionallyfamous.one-bit-bureau.inspector
# Layer presence plus the captured frame verifies the hosted application
# payload. Whole-screen OCR is unreliable for the intentionally small
# one-bit fact labels at the Test Lab's 1280x800 viewport.
sleep 0.5
screenshot "success-one-bit-bureau-05-dock-application-inspector"
wtype -k Escape
wait_until "Escape closes the application Inspector" 10 layer_absent regionallyfamous.one-bit-bureau.inspector
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock openMenuFirst) == "true" ]] ||
  fail "the dock menu reopens after Inspector dismissal"
wait_until "the dock app menu reopens" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getMenuOpen) == 'true' ]]"
wtype -k End
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock getMenuCurrentAction) == "toggleAutoHide" ]] ||
  fail "End reaches the last enabled dock command"
wtype -k Up
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock getMenuCurrentAction) == "manageIcons" ]] ||
  fail "Up skips dock-menu separators and reaches Manage Icons"
screenshot "success-one-bit-bureau-05a-dock-keyboard-menu"
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
setsid -f foot --app-id=one-bit-bureau-qa-ledger --title="Ledger Alpha" >/dev/null 2>&1
setsid -f foot --app-id=one-bit-bureau-qa-ledger --title="Ledger Beta" >/dev/null 2>&1
wait_until "the first proof window opens" 20 window_present '^one-bit-bureau-qa-one$'
wait_until "the second proof window opens" 20 window_present '^one-bit-bureau-qa-two$'
wait_until "both Window Ledger proof windows open" 20 \
  bash -c "(( \$(hyprctl -j clients | jq '[.[] | select(.class == \"one-bit-bureau-qa-ledger\")] | length') == 2 ))"
sleep 3
omarchy-shell notifications dismissAll >/dev/null 2>&1 || true

mapfile -t ledger_addresses < <(hyprctl -j clients | jq -er '.[] | select(.class == "one-bit-bureau-qa-ledger") | .address' | sort)
(( ${#ledger_addresses[@]} == 2 )) || fail "the Window Ledger proof exposes two stable addresses"
hyprctl dispatch 'hl.dsp.focus({ workspace = "2" })' >/dev/null 2>&1 ||
  hyprctl dispatch workspace 2 >/dev/null
sleep 0.5
ledger_move_record=$(move_window_with_live_identity "${ledger_addresses[1]}" 2)
IFS=$'\t' read -r ledger_move_state ledger_move_dispatcher ledger_move_address ledger_move_workspace ledger_move_monitor <<<"$ledger_move_record"
[[ $ledger_move_state == "confirmed" && $ledger_move_dispatcher =~ ^(lua|legacy)$
  && $ledger_move_address == "${ledger_addresses[1],,}" && $ledger_move_workspace == "2"
  && $ledger_move_monitor == "$monitor_name" ]] ||
  fail "the workspace helper emits its exact confirmed address, destination, dispatcher, and monitor record"
hyprctl dispatch 'hl.dsp.focus({ workspace = "1" })' >/dev/null 2>&1 ||
  hyprctl dispatch workspace 1 >/dev/null
wait_until "the Window Ledger tracks one proof window on Workspace 2" 15 \
  bash -c "hyprctl -j clients | jq -e --arg address '${ledger_addresses[1]}' 'any(.[]; .address == \$address and .workspace.id == 2)' >/dev/null"
hyprctl -j clients >"$ARTIFACTS/one-bit-bureau-window-ledger-clients.json"
omarchy-shell regionallyfamous.one-bit-bureau.dock getDockItemIds \
  >"$ARTIFACTS/one-bit-bureau-window-ledger-dock-ids.json"
omarchy-shell regionallyfamous.one-bit-bureau.dock getWindowCount one-bit-bureau-qa-ledger \
  >"$ARTIFACTS/one-bit-bureau-window-ledger-count.txt"
wait_until "the dock aggregates both proof windows under one app" 15 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getWindowCount one-bit-bureau-qa-ledger) == '2' ]]"
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock openWindowListForApp one-bit-bureau-qa-ledger) == "true" ]] ||
  fail "the dock opens the explicit Window Ledger"
wait_until "the Window Ledger panel opens" 10 layer_on_screen one-bit-bureau-window-ledger
sleep 0.5
screenshot "success-one-bit-bureau-07a-window-ledger"
omarchy-shell regionallyfamous.one-bit-bureau.dock closeWindowList >/dev/null
wait_until "the Window Ledger panel closes" 10 layer_absent one-bit-bureau-window-ledger
pass "One-Bit Bureau keeps one dock identity with truthful cross-workspace window state"

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
move_pointer_to $((monitor_width / 2)) $((monitor_height - 3)) "the pointer reaches the dock reveal edge"
wait_until "the dock reveal edge receives pointer hover" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getEdgeHovered) == 'true' ]]"
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

overview_move_address=$(hyprctl -j clients | jq -er '.[] | select(.class == "one-bit-bureau-qa-one") | .address' | head -n 1)
bash "$PLUGIN_DIR/components/dock/scripts/focus-window" "$overview_move_address" >/dev/null
wait_until "the overview move proof window is active on Workspace 1" 10 \
  bash -c "hyprctl -j activewindow | jq -e --arg address '$overview_move_address' '.address == \$address and .workspace.id == 1' >/dev/null"
omarchy-shell shell summon "$PLUGIN_ID" '{}' >/dev/null
wait_until "One-Bit Bureau overview opens" 20 layer_on_screen one-bit-bureau-window-overview
wait_until "the Workspace Board pins itself to the invoking output" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.overview getWorkspaceBoardMonitor) == '$monitor_name' ]]"
workspace_ids=$(omarchy-shell regionallyfamous.one-bit-bureau.overview getOrdinaryWorkspaceIds)
jq -e 'type == "array" and index(1) != null and index(2) != null and all(.[]; type == "number" and floor == . and . >= 1 and . <= 999)' \
  <<<"$workspace_ids" >/dev/null || fail "the Workspace Board exposes only attached ordinary numeric destinations"
workspace_unsupported_count=$(omarchy-shell regionallyfamous.one-bit-bureau.overview getUnsupportedWorkspaceCount)
[[ $workspace_unsupported_count =~ ^[0-9]+$ ]] || fail "the Workspace Board reports its excluded destination count"
sleep 2
screenshot "success-one-bit-bureau-12-overview"

wtype -k i
wait_until "the shared Inspector opens for the selected overview window" 15 layer_on_screen regionallyfamous.one-bit-bureau.inspector
sleep 0.5
screenshot "success-one-bit-bureau-12a-window-inspector"
wtype -k Escape
wait_until "Escape closes the window Inspector without dismissing Overview" 10 layer_absent regionallyfamous.one-bit-bureau.inspector
layer_on_screen one-bit-bureau-window-overview || fail "Overview remains open after Inspector dismissal"

wtype -M ctrl -k Right -m ctrl
wtype -M ctrl -M shift -k Return -m shift -m ctrl
wait_until "the overview workspace board moves the selected window to Workspace 2" 20 \
  bash -c "hyprctl -j clients | jq -e --arg address '$overview_move_address' 'any(.[]; .address == \$address and .workspace.id == 2)' >/dev/null"
wait_until "the Workspace Board reports the confirmed compositor postcondition" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.overview getWorkspaceMoveState) == 'confirmed' && \$(omarchy-shell regionallyfamous.one-bit-bureau.overview getWorkspaceNotice) == 'Move confirmed:'* ]]"
layer_on_screen one-bit-bureau-window-overview || fail "Overview remains open after a workspace move"
sleep 0.5
screenshot "success-one-bit-bureau-12b-workspace-board-move"
pass "One-Bit Bureau routes a selected window through the overview workspace board"

omarchy-shell shell hide "$PLUGIN_ID" >/dev/null
wait_until "One-Bit Bureau overview layer closes" 20 layer_absent one-bit-bureau-window-overview

omarchy-shell shell summon omarchy.menu '{"menu":"root"}' >/dev/null
wait_until "the One-Bit Bureau themed Omarchy menu opens" 15 layer_on_screen omarchy-menu
sleep 1
screenshot "success-one-bit-bureau-13-omarchy-menu"
wtype -k Escape
wait_until "Escape closes the Omarchy menu" 10 layer_absent omarchy-menu

# Exercise the stock Apps search route that current Omarchy serves through the
# same menu surface. This proves real results and focus without inventing a
# separate launcher implementation the host no longer exposes.
omarchy-menu summon apps >/dev/null
wait_until "the themed Apps search opens" 15 layer_on_screen omarchy-menu
wtype "foot"
wait_until "the themed Apps search paints a terminal result" 15 icon_manager_has_terminal
screenshot "success-one-bit-bureau-13a-apps-search"
omarchy-menu close >/dev/null
wait_until "the Apps search closes" 10 layer_absent omarchy-menu

# Open the canonical background selector and cancel it without changing the
# selected wallpaper. The layer itself is the stable contract; labels are not
# part of the stock invocation.
setsid -f omarchy-theme-bg-switcher >/dev/null 2>&1
wait_until "the One-Bit Bureau wallpaper picker opens" 20 layer_on_screen omarchy-image-selector
screenshot "success-one-bit-bureau-13b-wallpaper-picker"
wtype -k Escape
wait_until "Escape closes the wallpaper picker" 10 layer_absent omarchy-image-selector

# OSD is pure shell state here: a deterministic zero-duration model remains
# visible until explicitly closed and does not change display brightness.
[[ $(omarchy-shell osd show '{"icon":"brightness","message":"","value":"68","max":"100","progressText":"68%","duration":"0"}') == "ok" ]] ||
  fail "the One-Bit Bureau OSD opens through Omarchy IPC"
wait_until "the One-Bit Bureau OSD layer opens" 10 layer_on_screen omarchy-osd
wait_until "the One-Bit Bureau OSD paints its progress" 10 screen_contains "68%"
screenshot "success-one-bit-bureau-13c-osd"
omarchy-shell osd close >/dev/null
wait_until "the One-Bit Bureau OSD closes" 10 layer_absent omarchy-osd

# The dock tooltip consumes the native shell tooltip roles and is the only
# deterministic always-present tooltip target in this disposable guest.
tooltip_bounds=$(omarchy-shell regionallyfamous.one-bit-bureau.dock getIconBounds foot)
IFS=, read -r tooltip_x tooltip_y tooltip_width tooltip_height <<<"$tooltip_bounds"
[[ $tooltip_x =~ ^-?[0-9]+$ && $tooltip_y =~ ^-?[0-9]+$ &&
  $tooltip_width =~ ^[0-9]+$ && $tooltip_height =~ ^[0-9]+$ ]] ||
  fail "the dock exposes bounded tooltip target geometry"
move_pointer_to "$((monitor_x + tooltip_x + tooltip_width / 2))" \
  "$((monitor_y + tooltip_y + tooltip_height / 2))" \
  "the pointer reaches the deterministic dock tooltip target"
wait_until "the One-Bit Bureau dock tooltip paints" 10 screen_contains "Foot"
screenshot "success-one-bit-bureau-13d-tooltip"
move_pointer_to "$((monitor_x + logical_width / 2))" "$((monitor_y + logical_height / 2))" \
  "the pointer leaves the dock tooltip"

setsid -f foot --app-id=one-bit-bureau-qa-ansi --title="One-Bit Bureau ANSI" bash -lc \
  'printf "\033[1;37;40m  ONE-BIT BUREAU ANSI  \033[0m\n"; for c in 30 31 32 33 34 35 36 37; do printf "\033[${c}m██ COLOR ${c} ██\033[0m  "; done; printf "\n"; sleep 60' \
  >/dev/null 2>&1
wait_until "the ANSI palette proof opens" 20 window_present '^one-bit-bureau-qa-ansi$'
sleep 2
screenshot "success-one-bit-bureau-14-terminal-ansi"

omarchy-notification-wait 10 || fail "the Omarchy notification server is ready"
omarchy-notification-send -u normal "One-Bit Bureau" "Opaque paper notification proof" -t 30000 >/dev/null
wait_until "the One-Bit Bureau notification layer opens" 15 layer_on_screen omarchy-notifications
wait_until "the One-Bit Bureau notification content is recorded" 15 notification_has_proof
sleep 1
screenshot "success-one-bit-bureau-15-notification"
omarchy-shell notifications dismissAll >/dev/null 2>&1 || true

[[ $(omarchy-shell lock preview) == "ok" ]] || fail "the Omarchy lock preview opens"
wait_until "the One-Bit Bureau lock preview is visible" 15 layer_on_screen omarchy-lock-preview
wait_until "the One-Bit Bureau lock preview paints its idle prompt" 10 \
  screen_contains "Enter vault combination"
sleep 1
screenshot "success-one-bit-bureau-16-lock-preview"
omarchy-shell lock hidePreview >/dev/null
wait_until "the lock preview closes" 10 layer_absent omarchy-lock-preview

# A real session lock/unlock injects credentials and belongs to Omarchy's
# host-global graphical suite. The safe lock preview above proves this theme's
# lock surface without risking a stranded disposable guest.

# A real polkit request safely proves the idle and Cancel surfaces. Never
# submit an incorrect password here: failed authentication mutates PAM state.
pkexec /usr/bin/true >"$ARTIFACTS/one-bit-bureau-polkit.log" 2>&1 &
polkit_pid=$!
wait_until "the One-Bit Bureau polkit prompt opens" 15 layer_on_screen omarchy-polkit
wait_until "the One-Bit Bureau polkit prompt asks for authentication" 10 \
  screen_contains "Enter password"
screenshot "success-one-bit-bureau-16a-polkit-idle"
wtype -k Escape
wait_until "Escape cancels the One-Bit Bureau polkit prompt" 10 layer_absent omarchy-polkit
wait "$polkit_pid" 2>/dev/null || true
pass "One-Bit Bureau proves lock idle plus safe polkit idle and cancellation without failed authentication"

# The functional proof above intentionally uses hostile launchers, synthetic
# identities, and controllable terminal windows. Keep that evidence, then
# stage a separate public gallery with ordinary names and real Omarchy apps so
# release screenshots demonstrate a believable workday instead of QA debris.
close_windows '.*' || true
wait_until "the showcase starts without leftover application windows" 20 \
  bash -c "hyprctl -j clients | jq -e 'length == 0' >/dev/null"
focus_empty_desktop
wtype -k Escape
wait_until "the showcase dismisses the earlier functional receipt" 10 screen_lacks "cannot be routed"
screen_lacks "QA" || fail "the showcase desktop contains no QA labels"
prepare_showcase_desktop
focus_empty_desktop
screenshot "success-one-bit-bureau-21-showcase-desktop"

select_desktop_item_by_id "Field Guide.txt"
wtype -M ctrl -k i -m ctrl
wait_until "the showcase opens the shared Inspector for a normal document" 15 \
  layer_on_screen regionallyfamous.one-bit-bureau.inspector
sleep 0.5
screenshot "success-one-bit-bureau-22-showcase-inspector"
wtype -k Escape
wait_until "the showcase Inspector closes" 10 layer_absent regionallyfamous.one-bit-bureau.inspector

[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock openManageIcons) == "true" ]] ||
  fail "the showcase opens Manage Icons"
wait_until "the showcase icon manager opens" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getIconPickerMode) == 'manage' ]]"
wtype -M ctrl -k a -m ctrl
wtype -k BackSpace
wtype 'chromium'
sleep 1
wtype -k Down
wtype -k Return
wait_until "the showcase opens the browser icon picker" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getIconPickerMode) == 'picker' ]]"
screenshot "success-one-bit-bureau-23-showcase-icon-picker"
omarchy-shell regionallyfamous.one-bit-bureau.dock closeManageIcons >/dev/null
wait_until "the showcase icon picker closes" 10 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getIconPickerOpen) == 'false' ]]"

launch_showcase_apps
screenshot "success-one-bit-bureau-24-showcase-apps"

hyprctl -j clients | jq '[.[] | {
  address,
  class,
  initialClass,
  title,
  initialTitle,
  workspace
}]' >"$ARTIFACTS/one-bit-bureau-showcase-clients.json"

guide_address=$(hyprctl -j clients | jq -er '.[] | select((.title // "") | startswith("Bureau Field Guide")) | .address' | head -n 1)
release_address=$(hyprctl -j clients | jq -er '.[] | select((.title // "") | startswith("Bureau Release Desk")) | .address' | head -n 1)
writer_address=$(hyprctl -j clients | jq -er '.[] | select(.class == "libreoffice-writer") | .address' | head -n 1)
[[ -n $guide_address && -n $release_address && -n $writer_address ]] ||
  fail "the showcase exposes stable addresses for its real applications"

# The Workspace Board routes only to workspaces that presently exist. Create
# Desk 2 explicitly after the clean gallery reset, then return to Desk 1 once
# the Release Desk window keeps that destination alive.
hyprctl dispatch 'hl.dsp.focus({ workspace = "2" })' >/dev/null 2>&1 ||
  hyprctl dispatch workspace 2 >/dev/null
wait_until "the showcase creates Desk 2 before routing" 10 \
  bash -c "hyprctl -j activeworkspace | jq -e '.id == 2' >/dev/null"
move_window_with_live_identity "$release_address" 2 >/dev/null
wait_until "the showcase places one browser window on Desk 2" 15 \
  bash -c "hyprctl -j clients | jq -e --arg address '$release_address' 'any(.[]; .address == \$address and .workspace.id == 2)' >/dev/null"
hyprctl dispatch 'hl.dsp.focus({ workspace = "1" })' >/dev/null 2>&1 ||
  hyprctl dispatch workspace 1 >/dev/null
wait_until "the showcase dock groups both real browser windows" 15 \
  bash -c "[[ \$(omarchy-shell regionallyfamous.one-bit-bureau.dock getWindowCount chromium) == '2' ]]"
[[ $(omarchy-shell regionallyfamous.one-bit-bureau.dock openWindowListForApp chromium) == "true" ]] ||
  fail "the showcase opens Chromium's Window Ledger"
wait_until "the showcase Window Ledger opens" 10 layer_on_screen one-bit-bureau-window-ledger
sleep 0.5
screenshot "success-one-bit-bureau-25-showcase-window-ledger"
omarchy-shell regionallyfamous.one-bit-bureau.dock closeWindowList >/dev/null
wait_until "the showcase Window Ledger closes" 10 layer_absent one-bit-bureau-window-ledger

bash "$PLUGIN_DIR/components/dock/scripts/focus-window" "$writer_address" >/dev/null
wait_until "Writer is active before the showcase Overview opens" 10 \
  bash -c "hyprctl -j activewindow | jq -e --arg address '$writer_address' '.address == \$address and .workspace.id == 1' >/dev/null"
omarchy-shell shell summon "$PLUGIN_ID" '{}' >/dev/null
wait_until "the showcase Overview opens over real applications" 20 layer_on_screen one-bit-bureau-window-overview
sleep 2
screenshot "success-one-bit-bureau-26-showcase-overview"

wtype -M ctrl -k Right -m ctrl
wtype -M ctrl -M shift -k Return -m shift -m ctrl
wait_until "the showcase Workspace Board moves Writer to Desk 2" 20 \
  bash -c "hyprctl -j clients | jq -e --arg address '$writer_address' 'any(.[]; .address == \$address and .workspace.id == 2)' >/dev/null"
layer_on_screen one-bit-bureau-window-overview || fail "the showcase Overview stays open after moving Writer"
sleep 0.5
screenshot "success-one-bit-bureau-27-showcase-workspace-board"
omarchy-shell shell hide "$PLUGIN_ID" >/dev/null
wait_until "the showcase Overview closes" 20 layer_absent one-bit-bureau-window-overview

bash "$PLUGIN_DIR/components/dock/scripts/focus-window" "$guide_address" >/dev/null
wait_until "the Bureau Field Guide is active for the final showcase frame" 10 \
  bash -c "hyprctl -j activewindow | jq -e --arg address '$guide_address' '.address == \$address' >/dev/null"
omarchy-notification-send -u normal "Desk ready" "Files, Web, Writer, and every window accounted for." -t 30000 >/dev/null
wait_until "the showcase notification opens" 15 layer_on_screen omarchy-notifications
wait_until "the showcase notification paints its workday message" 15 screen_contains "Desk ready"
sleep 1
screenshot "success-one-bit-bureau-28-showcase-notification"
omarchy-shell notifications dismissAll >/dev/null 2>&1 || true

restore_showcase_state
wait_until "the functional Desktop fixture returns after the showcase" 20 \
  bash -c "[[ -f '$HOME/Desktop/Welcome.txt' && -f '$HOME/Desktop/One-Bit Bureau Photo.png' ]]"
pass "One-Bit Bureau keeps functional proof separate from a clean real-app gallery"

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
  timeout 30 omarchy theme set "$ORIGINAL_THEME" >/dev/null
fi
rm -rf "$PLUGIN_DIR"
rm -rf "$THEME_TARGET"
omarchy-shell shell rescanPlugins >/dev/null
wait_until "the local fixture checkout is absent" 15 public_plugin_absent
[[ ! -e $PLUGIN_DIR && ! -e $THEME_TARGET ]] || fail "the local fixture install is fully cleaned"
pass "the local fixture install is fully cleaned before public lifecycle testing"
screenshot "success-one-bit-bureau-17-local-fixture-removed"

# Exact public lifecycle. This intentionally runs the literal hosted bootstrap
# through a real pseudo-terminal. Comparing the test file's digest makes the
# run fail until public main contains the exact acceptance code being executed.
mkdir -p "$BUREAU_CONFIG"
printf 'preserve One-Bit Bureau user state\n' >"$BUREAU_CONFIG/lifecycle-user-data.txt"
public_lifecycle_active=true
omarchy plugin add "$PUBLIC_REPO_URL" --yes
wait_until "the interrupted public install leaves a disabled checkout" 15 \
  bash -c "omarchy plugin list --json | jq -e --arg id '$PLUGIN_ID' 'any(.[]; .id == \$id and .enabled == false)'"
printf 'y\n' | script -qefc "bash -lc 'bash <(curl -fsSL $PUBLIC_INSTALL_URL)'" "$PUBLIC_INSTALL_LOG"
grep -Fq "continuing now with the matching theme, fonts, branding, and activation" "$PUBLIC_INSTALL_LOG" ||
  fail "the public bootstrap does not explain and continue past Omarchy's temporary disabled state"
pass "the literal public bootstrap recovers Omarchy's temporary disabled checkout"
[[ -d $PLUGIN_DIR/.git ]] || fail "the public plugin install is Git-managed"
public_acceptance_hash=$(sha256sum "$PLUGIN_DIR/test/omarchy-acceptance.sh" | awk '{print $1}')
[[ $public_acceptance_hash == "$fixture_acceptance_hash" ]] ||
  fail "public main contains the exact acceptance test under execution"
pass "public main contains the exact acceptance test under execution"

wait_until "the public One-Bit Bureau plugin activates" 30 \
  bash -c "omarchy plugin list --json | jq -e --arg id '$PLUGIN_ID' 'any(.[]; .id == \$id and .enabled == true)'"
wait_until "the public One-Bit Bureau dock mounts" 20 layer_on_screen one-bit-bureau-dock
[[ -f $STATE_FILE && ! -L $STATE_FILE ]] || fail "public setup records source ownership"
PUBLIC_THEME_MODE=$(jq -er '.installed.themeInstallMode' "$STATE_FILE")
PUBLIC_SOURCE_ID=$(jq -er '.installed.themeSourceId' "$STATE_FILE")
[[ -L $THEME_TARGET ]] || fail "public setup installs the theme as an owned symlink"
expected_public_theme_mode="plugin-link"
if [[ -n ${OMARCHY_PATH:-} ]] &&
  [[ -x $OMARCHY_PATH/bin/omarchy-theme-source-inspect ]] &&
  [[ -x $OMARCHY_PATH/bin/omarchy-theme-source-install ]] &&
  [[ -x $OMARCHY_PATH/bin/omarchy-theme-source-update ]] &&
  [[ -x $OMARCHY_PATH/bin/omarchy-theme-source-detach ]]; then
  expected_public_theme_mode="source"
fi
[[ $PUBLIC_THEME_MODE == "$expected_public_theme_mode" ]] ||
  fail "public setup selected $PUBLIC_THEME_MODE instead of the supported $expected_public_theme_mode mode"
if [[ $PUBLIC_THEME_MODE == "source" ]]; then
  PUBLIC_SOURCE_PATH="$THEME_SOURCES_DIR/$PUBLIC_SOURCE_ID"
  [[ -d $PUBLIC_SOURCE_PATH/.git && ! -L $PUBLIC_SOURCE_PATH ]] ||
    fail "public setup creates a safe theme-source checkout"
  [[ $(realpath "$THEME_TARGET") == "$(realpath "$PUBLIC_SOURCE_PATH/themes/$THEME_NAME")" ]] ||
    fail "the installed theme link resolves inside its recorded source"
elif [[ $PUBLIC_THEME_MODE == "plugin-link" ]]; then
  [[ -z $PUBLIC_SOURCE_ID ]] || fail "plugin-linked theme records no separate source ID"
  [[ $(realpath "$THEME_TARGET") == "$(realpath "$PLUGIN_DIR/themes/$THEME_NAME")" ]] ||
    fail "the installed theme link resolves inside its plugin checkout"
else
  fail "public setup records a supported theme installation mode"
fi
assert_public_commit_alignment || fail "the public plugin and owned theme align with public main"
pass "the public plugin, owned theme, ownership record, and main branch align"
[[ -x $COMMAND_TARGET && -d $FONT_TARGET ]] || fail "public setup installs the command and bundled fonts"
screenshot "success-one-bit-bureau-18-public-install"

# Diagnostics and app chrome are deliberately command-line surfaces. Prove
# their byte-level ownership behavior without pretending they add a visual
# shell scene that deserves a screenshot.
doctor_fingerprint_before=$(path_fingerprint \
  "$STATE_FILE" "$BUREAU_CONFIG" "$GTK3_SETTINGS" "$APP_CHROME_THEME" "$APP_CHROME_STATE" "$APP_CHROME_BACKUP")
"$COMMAND_TARGET" doctor >"$ARTIFACTS/one-bit-bureau-doctor.log"
grep -Fq 'One-Bit Bureau doctor (read-only)' "$ARTIFACTS/one-bit-bureau-doctor.log" ||
  fail "doctor identifies its default read-only boundary"
grep -Fq 'doctor made no changes' "$ARTIFACTS/one-bit-bureau-doctor.log" ||
  fail "doctor reports that it made no changes"
doctor_fingerprint_after=$(path_fingerprint \
  "$STATE_FILE" "$BUREAU_CONFIG" "$GTK3_SETTINGS" "$APP_CHROME_THEME" "$APP_CHROME_STATE" "$APP_CHROME_BACKUP")
[[ $doctor_fingerprint_after == "$doctor_fingerprint_before" ]] ||
  fail "doctor is byte-for-byte read-only across every One-Bit Bureau and GTK3 ownership path"
if "$COMMAND_TARGET" doctor --repair unsupported >"$ARTIFACTS/one-bit-bureau-doctor-invalid-repair.log" 2>&1; then
  fail "doctor refuses an unrecognized repair instead of broadening its write boundary"
fi
[[ $(path_fingerprint "$STATE_FILE" "$BUREAU_CONFIG" "$GTK3_SETTINGS" "$APP_CHROME_THEME" "$APP_CHROME_STATE" "$APP_CHROME_BACKUP") == "$doctor_fingerprint_before" ]] ||
  fail "a refused doctor repair leaves every inspected path unchanged"
pass "One-Bit Bureau doctor is read-only by default and rejects repairs outside its one named boundary"

app_chrome_off_fingerprint=$(path_fingerprint \
  "$GTK3_SETTINGS" "$APP_CHROME_THEME" "$APP_CHROME_STATE" "$APP_CHROME_BACKUP")
"$COMMAND_TARGET" app-chrome preview >"$ARTIFACTS/one-bit-bureau-app-chrome-preview.log"
"$COMMAND_TARGET" app-chrome status >"$ARTIFACTS/one-bit-bureau-app-chrome-status-off.log"
grep -Fq 'no changes made' "$ARTIFACTS/one-bit-bureau-app-chrome-preview.log" ||
  fail "app-chrome preview names its no-write behavior"
grep -Fq 'preview: off' "$ARTIFACTS/one-bit-bureau-app-chrome-status-off.log" ||
  fail "app-chrome status truthfully reports off"
[[ $(path_fingerprint "$GTK3_SETTINGS" "$APP_CHROME_THEME" "$APP_CHROME_STATE" "$APP_CHROME_BACKUP") == "$app_chrome_off_fingerprint" ]] ||
  fail "app-chrome preview and status are byte-for-byte read-only"

"$COMMAND_TARGET" app-chrome on >"$ARTIFACTS/one-bit-bureau-app-chrome-on.log"
[[ -f $APP_CHROME_THEME/gtk-3.0/gtk.css && ! -L $APP_CHROME_THEME/gtk-3.0/gtk.css && -f $APP_CHROME_STATE && ! -L $APP_CHROME_STATE ]] ||
  fail "app-chrome on creates only its user-scoped GTK3 theme and ownership record"
grep -Fxq 'gtk-theme-name=One-Bit-Bureau-GTK3' "$GTK3_SETTINGS" ||
  fail "app-chrome on selects the explicit GTK3 preview theme"
"$COMMAND_TARGET" app-chrome status >"$ARTIFACTS/one-bit-bureau-app-chrome-status-on.log"
grep -Fq 'preview: on' "$ARTIFACTS/one-bit-bureau-app-chrome-status-on.log" ||
  fail "app-chrome status truthfully reports on"
"$COMMAND_TARGET" app-chrome off >"$ARTIFACTS/one-bit-bureau-app-chrome-off.log"
[[ $(path_fingerprint "$GTK3_SETTINGS" "$APP_CHROME_THEME" "$APP_CHROME_STATE" "$APP_CHROME_BACKUP") == "$app_chrome_off_fingerprint" ]] ||
  fail "app-chrome off restores the exact prior GTK3 state and removes only owned files"

"$COMMAND_TARGET" app-chrome on >/dev/null
app_chrome_on_fingerprint=$(path_fingerprint \
  "$GTK3_SETTINGS" "$APP_CHROME_THEME" "$APP_CHROME_STATE" "$APP_CHROME_BACKUP")
"$COMMAND_TARGET" doctor >"$ARTIFACTS/one-bit-bureau-doctor-app-chrome-on.log"
[[ $(path_fingerprint "$GTK3_SETTINGS" "$APP_CHROME_THEME" "$APP_CHROME_STATE" "$APP_CHROME_BACKUP") == "$app_chrome_on_fingerprint" ]] ||
  fail "doctor reports an enabled app-chrome preview without disabling it implicitly"
"$COMMAND_TARGET" doctor --repair app-chrome-off >"$ARTIFACTS/one-bit-bureau-doctor-repair.log"
[[ $(path_fingerprint "$GTK3_SETTINGS" "$APP_CHROME_THEME" "$APP_CHROME_STATE" "$APP_CHROME_BACKUP") == "$app_chrome_off_fingerprint" ]] ||
  fail "doctor's sole repair delegates to the ownership-safe app-chrome off path"
pass "GTK3 app chrome remains opt-in, previewable, exactly reversible, and outside GTK4/libadwaita"

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
pass "the public update command keeps plugin and owned theme aligned"

public_theme_source_state=""
if [[ $PUBLIC_THEME_MODE == "source" ]]; then
  public_theme_source_state="$THEME_SOURCE_STATE_DIR/$PUBLIC_SOURCE_ID/installed/$THEME_NAME"
fi
"$COMMAND_TARGET" remove
public_lifecycle_active=false
wait_until "the public plugin is removed" 20 public_plugin_absent
[[ ! -e $PLUGIN_DIR && ! -L $PLUGIN_DIR && ! -e $THEME_TARGET && ! -L $THEME_TARGET && ! -e $STATE_FILE ]] ||
  fail "public removal clears plugin, theme link, and ownership state"
[[ ! -e $FONT_TARGET && ! -e $COMMAND_TARGET ]] ||
  fail "public removal clears owned fonts and command"
[[ -z $public_theme_source_state || ! -e $public_theme_source_state ]] || fail "public removal detaches the theme from its source"
[[ -f $BUREAU_CONFIG/lifecycle-user-data.txt && -f $HOME/Desktop/Welcome.txt && -f $HOME/Desktop/One-Bit\ Bureau\ Photo.png ]] ||
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
