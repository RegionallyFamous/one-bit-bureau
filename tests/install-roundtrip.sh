#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export TEST_ROOT="$ROOT"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"
mkdir -p "$BIN"

printf '%s\n' '#!/bin/bash' >"$BIN/omarchy-shell"
printf '%s\n' 'exit 0' >>"$BIN/omarchy-shell"
chmod +x "$BIN/omarchy-shell"

printf '%s\n' '#!/bin/bash' >"$BIN/xdg-user-dir"
printf '%s\n' 'printf "%s\n" "$TEST_DESKTOP"' >>"$BIN/xdg-user-dir"
chmod +x "$BIN/xdg-user-dir"

printf '%s\n' '#!/bin/bash' >"$BIN/git"
printf '%s\n' 'set -euo pipefail' >>"$BIN/git"
printf '%s\n' 'last=${!#}' >>"$BIN/git"
printf '%s\n' 'if [[ $* == *"config --get remote.origin.url"* ]]; then echo "https://example.invalid/paper-jam.git"' >>"$BIN/git"
printf '%s\n' 'elif [[ $last == "refs/remotes/origin/HEAD" ]]; then echo "origin/main"' >>"$BIN/git"
printf '%s\n' 'elif [[ $last == "HEAD" ]]; then echo "main"' >>"$BIN/git"
printf '%s\n' 'else exit 1; fi' >>"$BIN/git"
chmod +x "$BIN/git"

printf '%s\n' '#!/bin/bash' >"$BIN/omarchy"
printf '%s\n' 'set -euo pipefail' >>"$BIN/omarchy"
printf '%s\n' 'printf "%s\n" "$*" >>"$TEST_LOG"' >>"$BIN/omarchy"
printf '%s\n' 'shell_config="$HOME/.config/omarchy/shell.json"' >>"$BIN/omarchy"
printf '%s\n' 'theme_state="$HOME/.local/state/omarchy/current/theme.name"' >>"$BIN/omarchy"
printf '%s\n' 'case "$1 $2" in' >>"$BIN/omarchy"
printf '%s\n' '  "plugin list") [[ ${FAIL_PLUGIN_LIST:-} != 1 ]] || exit 1; printf "%s\n" "${PLUGIN_LIST_JSON:-[]}" ;;' >>"$BIN/omarchy"
printf '%s\n' '  "plugin validate")' >>"$BIN/omarchy"
printf '%s\n' '    target=$3' >>"$BIN/omarchy"
printf '%s\n' '    [[ ! -e $target/.git ]]' >>"$BIN/omarchy"
printf '%s\n' '    jq -e '\''.id == "io.github.regionallyfamous.alumina" and .name == "Paper Jam ’84"'\'' "$target/manifest.json" >/dev/null' >>"$BIN/omarchy"
printf '%s\n' '    ;;' >>"$BIN/omarchy"
printf '%s\n' '  "plugin add")' >>"$BIN/omarchy"
printf '%s\n' '    target="$HOME/.config/omarchy/plugins/io.github.regionallyfamous.alumina"' >>"$BIN/omarchy"
printf '%s\n' '    mkdir -p "$target"' >>"$BIN/omarchy"
printf '%s\n' '    cp "$TEST_ROOT/manifest.json" "$target/manifest.json"' >>"$BIN/omarchy"
printf '%s\n' '    [[ ${FAIL_PLUGIN_ADD_PARTIAL:-0} != 1 ]] || exit 1' >>"$BIN/omarchy"
printf '%s\n' '    ;;' >>"$BIN/omarchy"
printf '%s\n' '  "plugin remove") rm -rf "$HOME/.config/omarchy/plugins/$3" ;;' >>"$BIN/omarchy"
printf '%s\n' '  "bar position")' >>"$BIN/omarchy"
printf '%s\n' '    jq --arg value "$3" '\''.bar.position = $value'\'' "$shell_config" >"$shell_config.tmp"' >>"$BIN/omarchy"
printf '%s\n' '    mv "$shell_config.tmp" "$shell_config"' >>"$BIN/omarchy"
printf '%s\n' '    ;;' >>"$BIN/omarchy"
printf '%s\n' '  "bar transparent")' >>"$BIN/omarchy"
printf '%s\n' '    jq --argjson value "$3" '\''.bar.transparent = $value'\'' "$shell_config" >"$shell_config.tmp"' >>"$BIN/omarchy"
printf '%s\n' '    mv "$shell_config.tmp" "$shell_config"' >>"$BIN/omarchy"
printf '%s\n' '    ;;' >>"$BIN/omarchy"
printf '%s\n' '  "theme set")' >>"$BIN/omarchy"
printf '%s\n' '    [[ ${FAIL_THEME:-} != "$3" ]] || exit 1' >>"$BIN/omarchy"
printf '%s\n' '    mkdir -p "$(dirname "$theme_state")"' >>"$BIN/omarchy"
printf '%s\n' '    printf "%s\n" "$3" >"$theme_state"' >>"$BIN/omarchy"
printf '%s\n' '    ;;' >>"$BIN/omarchy"
printf '%s\n' '  "theme install")' >>"$BIN/omarchy"
printf '%s\n' '    mkdir -p "$HOME/.config/omarchy/themes/paper-jam-84"' >>"$BIN/omarchy"
printf '%s\n' '    [[ ${FAIL_THEME_INSTALL_PARTIAL:-0} != 1 ]] || exit 1' >>"$BIN/omarchy"
printf '%s\n' '    ;;' >>"$BIN/omarchy"
printf '%s\n' '  "theme remove") rm -rf "$HOME/.config/omarchy/themes/$3" ;;' >>"$BIN/omarchy"
printf '%s\n' 'esac' >>"$BIN/omarchy"
chmod +x "$BIN/omarchy"

seed_home() {
  local home=$1
  mkdir -p "$home/.config/omarchy" "$home/.local/state/omarchy/current"
  printf '%s\n' '{"bar":{"position":"bottom","transparent":true}}' >"$home/.config/omarchy/shell.json"
  printf '%s\n' 'catppuccin' >"$home/.local/state/omarchy/current/theme.name"
}

echo "== local setup installs an atomic minimal payload and uninstall restores owned state"
HOME_ONE="$WORK/home-one"
seed_home "$HOME_ONE"
export TEST_DESKTOP="$HOME_ONE/Desk Files"
export TEST_LOG="$WORK/roundtrip.log"
HOME="$HOME_ONE" PATH="$BIN:$PATH" bash "$ROOT/setup" --local

PLUGIN="$HOME_ONE/.config/omarchy/plugins/io.github.regionallyfamous.alumina"
THEME="$HOME_ONE/.config/omarchy/themes/paper-jam-84"
STATE="$HOME_ONE/.local/state/omarchy/plugins/io.github.regionallyfamous.alumina/install-state.json"
[[ -f $PLUGIN/manifest.json && -d $THEME && -f $STATE ]]
[[ ! -e $PLUGIN/.git && ! -d $PLUGIN/components/dock/tests && ! -d $PLUGIN/components/desktop/tests ]]
[[ -d $TEST_DESKTOP ]]
jq -e '.pluginOwned and .themeOwned and .previous.theme == "catppuccin" and .previous.barPosition == "bottom" and .previous.barTransparent' "$STATE" >/dev/null
printf '%s\n' 'keep' >"$TEST_DESKTOP/user-file.txt"

HOME="$HOME_ONE" PATH="$BIN:$PATH" bash "$ROOT/uninstall"
[[ ! -e $PLUGIN && ! -e $THEME && ! -e $STATE ]]
[[ $(<"$HOME_ONE/.local/state/omarchy/current/theme.name") == "catppuccin" ]]
jq -e '.bar.position == "bottom" and .bar.transparent == true' "$HOME_ONE/.config/omarchy/shell.json" >/dev/null
[[ -f $TEST_DESKTOP/user-file.txt ]]

echo "== setup refuses an unowned theme collision without touching it"
HOME_TWO="$WORK/home-two"
seed_home "$HOME_TWO"
mkdir -p "$HOME_TWO/.config/omarchy/themes/paper-jam-84"
printf '%s\n' 'keep' >"$HOME_TWO/.config/omarchy/themes/paper-jam-84/sentinel"
export TEST_DESKTOP="$HOME_TWO/Desktop"
export TEST_LOG="$WORK/collision.log"
if HOME="$HOME_TWO" PATH="$BIN:$PATH" bash "$ROOT/setup" --local >/dev/null 2>&1; then
  echo "setup accepted an unowned theme collision" >&2
  exit 1
fi
[[ -f $HOME_TWO/.config/omarchy/themes/paper-jam-84/sentinel ]]
[[ ! -e $HOME_TWO/.config/omarchy/plugins/io.github.regionallyfamous.alumina ]]

echo "== a late activation failure rolls back plugin, theme, and bar changes"
HOME_THREE="$WORK/home-three"
seed_home "$HOME_THREE"
export TEST_DESKTOP="$HOME_THREE/Desktop"
export TEST_LOG="$WORK/rollback.log"
export FAIL_THEME="paper-jam-84"
if HOME="$HOME_THREE" PATH="$BIN:$PATH" bash "$ROOT/setup" --local >/dev/null 2>&1; then
  echo "setup unexpectedly survived a theme activation failure" >&2
  exit 1
fi
unset FAIL_THEME
[[ ! -e $HOME_THREE/.config/omarchy/plugins/io.github.regionallyfamous.alumina ]]
[[ ! -e $HOME_THREE/.config/omarchy/themes/paper-jam-84 ]]
[[ ! -e $HOME_THREE/.local/state/omarchy/plugins/io.github.regionallyfamous.alumina/install-state.json ]]
jq -e '.bar.position == "bottom" and .bar.transparent == true' "$HOME_THREE/.config/omarchy/shell.json" >/dev/null

echo "== setup stops when installed-plugin discovery is unavailable"
HOME_FOUR="$WORK/home-four"
seed_home "$HOME_FOUR"
export TEST_DESKTOP="$HOME_FOUR/Desktop"
export TEST_LOG="$WORK/plugin-list-failure.log"
export FAIL_PLUGIN_LIST=1
if HOME="$HOME_FOUR" PATH="$BIN:$PATH" bash "$ROOT/setup" --local >/dev/null 2>&1; then
  echo "setup continued without a trustworthy installed-plugin list" >&2
  exit 1
fi
unset FAIL_PLUGIN_LIST
[[ ! -e $HOME_FOUR/.config/omarchy/plugins/io.github.regionallyfamous.alumina ]]
[[ ! -e $HOME_FOUR/.config/omarchy/themes/paper-jam-84 ]]
[[ ! -e $HOME_FOUR/.local/state/omarchy/plugins/io.github.regionallyfamous.alumina/install-state.json ]]

echo "== setup refuses enabled standalone-plugin conflicts"
HOME_CONFLICT="$WORK/home-conflict"
seed_home "$HOME_CONFLICT"
export TEST_DESKTOP="$HOME_CONFLICT/Desktop"
export TEST_LOG="$WORK/plugin-conflict.log"
export PLUGIN_LIST_JSON='[{"id":"henri.desktop-icons","enabled":true}]'
if HOME="$HOME_CONFLICT" PATH="$BIN:$PATH" bash "$ROOT/setup" --local >/dev/null 2>&1; then
  echo "setup accepted an enabled standalone replacement" >&2
  exit 1
fi
unset PLUGIN_LIST_JSON
[[ ! -e $HOME_CONFLICT/.config/omarchy/plugins/io.github.regionallyfamous.alumina ]]
[[ ! -e $HOME_CONFLICT/.config/omarchy/themes/paper-jam-84 ]]
[[ ! -e $HOME_CONFLICT/.local/state/omarchy/plugins/io.github.regionallyfamous.alumina/install-state.json ]]

echo "== uninstall refuses a tampered ownership target"
HOME_FIVE="$WORK/home-five"
seed_home "$HOME_FIVE"
export TEST_DESKTOP="$HOME_FIVE/Desktop"
export TEST_LOG="$WORK/tampered-state.log"
HOME="$HOME_FIVE" PATH="$BIN:$PATH" bash "$ROOT/setup" --local >/dev/null
STATE_FIVE="$HOME_FIVE/.local/state/omarchy/plugins/io.github.regionallyfamous.alumina/install-state.json"
jq '.theme = "catppuccin"' "$STATE_FIVE" >"$STATE_FIVE.tmp"
mv "$STATE_FIVE.tmp" "$STATE_FIVE"
if HOME="$HOME_FIVE" PATH="$BIN:$PATH" bash "$ROOT/uninstall" >/dev/null 2>&1; then
  echo "uninstall accepted a tampered theme ownership target" >&2
  exit 1
fi
[[ -e $HOME_FIVE/.config/omarchy/plugins/io.github.regionallyfamous.alumina ]]
[[ -e $HOME_FIVE/.config/omarchy/themes/paper-jam-84 ]]
jq '.theme = "paper-jam-84"' "$STATE_FIVE" >"$STATE_FIVE.tmp"
mv "$STATE_FIVE.tmp" "$STATE_FIVE"
HOME="$HOME_FIVE" PATH="$BIN:$PATH" bash "$ROOT/uninstall" >/dev/null

echo "== uninstall leaves settings the user changed after setup"
HOME_SIX="$WORK/home-six"
seed_home "$HOME_SIX"
export TEST_DESKTOP="$HOME_SIX/Desktop"
export TEST_LOG="$WORK/user-settings.log"
HOME="$HOME_SIX" PATH="$BIN:$PATH" bash "$ROOT/setup" --local >/dev/null
printf '%s\n' 'solarized' >"$HOME_SIX/.local/state/omarchy/current/theme.name"
printf '%s\n' '{"bar":{"position":"left","transparent":true}}' >"$HOME_SIX/.config/omarchy/shell.json"
HOME="$HOME_SIX" PATH="$BIN:$PATH" bash "$ROOT/uninstall" >/dev/null
[[ $(<"$HOME_SIX/.local/state/omarchy/current/theme.name") == "solarized" ]]
jq -e '.bar.position == "left" and .bar.transparent == true' "$HOME_SIX/.config/omarchy/shell.json" >/dev/null

echo "== remote plugin failure removes a partially created target"
HOME_SEVEN="$WORK/home-seven"
seed_home "$HOME_SEVEN"
export TEST_DESKTOP="$HOME_SEVEN/Desktop"
export TEST_LOG="$WORK/partial-plugin.log"
export FAIL_PLUGIN_ADD_PARTIAL=1
if HOME="$HOME_SEVEN" PATH="$BIN:$PATH" bash "$ROOT/setup" >"$WORK/partial-plugin-setup.log" 2>&1; then
  echo "remote setup survived a partial plugin-add failure" >&2
  exit 1
fi
unset FAIL_PLUGIN_ADD_PARTIAL
[[ ! -e $HOME_SEVEN/.config/omarchy/plugins/io.github.regionallyfamous.alumina ]] || {
  cat "$WORK/partial-plugin-setup.log" >&2
  echo "partial plugin target survived rollback" >&2
  exit 1
}
[[ ! -e $HOME_SEVEN/.config/omarchy/themes/paper-jam-84 ]]
[[ ! -e $HOME_SEVEN/.local/state/omarchy/plugins/io.github.regionallyfamous.alumina/install-state.json ]]

echo "== remote theme failure removes both partial targets"
HOME_EIGHT="$WORK/home-eight"
seed_home "$HOME_EIGHT"
export TEST_DESKTOP="$HOME_EIGHT/Desktop"
export TEST_LOG="$WORK/partial-theme.log"
export FAIL_THEME_INSTALL_PARTIAL=1
if HOME="$HOME_EIGHT" PATH="$BIN:$PATH" bash "$ROOT/setup" >"$WORK/partial-theme-setup.log" 2>&1; then
  echo "remote setup survived a partial theme-install failure" >&2
  exit 1
fi
unset FAIL_THEME_INSTALL_PARTIAL
[[ ! -e $HOME_EIGHT/.config/omarchy/plugins/io.github.regionallyfamous.alumina ]] || {
  cat "$WORK/partial-theme-setup.log" >&2
  echo "plugin target survived theme rollback" >&2
  exit 1
}
[[ ! -e $HOME_EIGHT/.config/omarchy/themes/paper-jam-84 ]]
[[ ! -e $HOME_EIGHT/.local/state/omarchy/plugins/io.github.regionallyfamous.alumina/install-state.json ]]

echo "setup/uninstall roundtrip tests passed"
