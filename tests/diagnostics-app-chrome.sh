#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

PLUGIN_ID="io.github.regionallyfamous.one-bit-bureau"
HOME_DIR="$WORK/home"
BIN="$WORK/bin"
PLUGIN="$HOME_DIR/.config/omarchy/plugins/$PLUGIN_ID"
STATE_DIR="$HOME_DIR/.local/state/omarchy/plugins/$PLUGIN_ID"
GTK_SETTINGS="$HOME_DIR/.config/gtk-3.0/settings.ini"
GTK_THEME="$HOME_DIR/.local/share/themes/One-Bit-Bureau-GTK3"
APP_STATE="$STATE_DIR/app-chrome-state.json"

mkdir -p "$BIN" "$PLUGIN/scripts" "$PLUGIN/app-chrome/gtk-3.0" "$PLUGIN/components/dock/assets/app-icons" "$STATE_DIR" "$HOME_DIR/Desktop"
cp "$ROOT/one-bit-bureau" "$PLUGIN/one-bit-bureau"
cp "$ROOT/scripts/one-bit-bureau-doctor" "$PLUGIN/scripts/one-bit-bureau-doctor"
cp "$ROOT/scripts/one-bit-bureau-app-chrome.py" "$PLUGIN/scripts/one-bit-bureau-app-chrome.py"
cp "$ROOT/app-chrome/index.theme" "$PLUGIN/app-chrome/index.theme"
cp "$ROOT/app-chrome/gtk-3.0/gtk.css" "$PLUGIN/app-chrome/gtk-3.0/gtk.css"
cp "$ROOT/manifest.json" "$PLUGIN/manifest.json"
cp "$ROOT/components/dock/assets/app-icons/pack.json" "$PLUGIN/components/dock/assets/app-icons/pack.json"
while IFS= read -r role; do
  : >"$PLUGIN/components/dock/assets/app-icons/$role.png"
done < <(jq -r '.roles[].id' "$PLUGIN/components/dock/assets/app-icons/pack.json")

mkdir -p "$HOME_DIR/.config/omarchy/themes" "$HOME_DIR/.local/state/omarchy/current"
mkdir -p "$PLUGIN/themes/one-bit-bureau"
ln -s "$PLUGIN/themes/one-bit-bureau" "$HOME_DIR/.config/omarchy/themes/one-bit-bureau"
printf '%s\n' 'one-bit-bureau' >"$HOME_DIR/.local/state/omarchy/current/theme.name"
jq -n --arg id "$PLUGIN_ID" '{schemaVersion: 3, pluginId: $id, product: "One-Bit Bureau", theme: "one-bit-bureau", pluginOwned: true, themeOwned: true, installed: {themeInstallMode: "plugin-link", themeSourceId: ""}}' >"$STATE_DIR/install-state.json"

cat >"$BIN/omarchy" <<'EOF'
#!/bin/bash
if [[ $* == "plugin list --json" ]]; then
  printf '%s\n' '[{"id":"io.github.regionallyfamous.one-bit-bureau","enabled":true}]'
fi
EOF
cat >"$BIN/omarchy-shell" <<'EOF'
#!/bin/bash
exit 0
EOF
cat >"$BIN/xdg-user-dir" <<'EOF'
#!/bin/bash
printf '%s\n' "$HOME/Desktop"
EOF
chmod +x "$BIN/omarchy" "$BIN/omarchy-shell" "$BIN/xdg-user-dir"

run() {
  HOME="$HOME_DIR" PATH="$BIN:$PATH" bash "$PLUGIN/one-bit-bureau" "$@"
}

run_with_other_state_home() {
  HOME="$HOME_DIR" XDG_STATE_HOME="$WORK/not-omarchy-plugin-state" PATH="$BIN:$PATH" bash "$PLUGIN/one-bit-bureau" "$@"
}

echo "== preview and status do not write"
mkdir -p "$(dirname "$GTK_SETTINGS")"
printf '%s\n' '[Settings]' 'gtk-theme-name=Adwaita' 'gtk-enable-animations=true' >"$GTK_SETTINGS"
before=$(shasum -a 256 "$GTK_SETTINGS" | awk '{print $1}')
run app-chrome preview >"$WORK/preview.log"
run app-chrome status >"$WORK/status.log"
[[ $(shasum -a 256 "$GTK_SETTINGS" | awk '{print $1}') == "$before" ]]
[[ ! -e $APP_STATE && ! -e $GTK_THEME ]]
grep -Fq 'no changes made' "$WORK/preview.log"
grep -Fq 'preview: off' "$WORK/status.log"

echo "== on records exact settings and off restores them"
original=$(<"$GTK_SETTINGS")
run_with_other_state_home app-chrome on >"$WORK/on.log"
[[ -f $APP_STATE && -f $GTK_THEME/gtk-3.0/gtk.css ]]
[[ ! -e $WORK/not-omarchy-plugin-state ]]
grep -Fxq 'gtk-theme-name=One-Bit-Bureau-GTK3' "$GTK_SETTINGS"
jq -e '.previousSettingsPresent == true and .mechanism == "gtk3-user-theme"' "$APP_STATE" >/dev/null
run app-chrome off >"$WORK/off.log"
[[ $(<"$GTK_SETTINGS") == "$original" ]]
[[ ! -e $APP_STATE && ! -e $GTK_THEME ]]

echo "== off retains ownership when modified settings still select the preview"
run app-chrome on
printf '%s\n' '; user changed this after preview' >>"$GTK_SETTINGS"
printf '%s\n' 'user asset' >>"$GTK_THEME/gtk-3.0/gtk.css"
if run app-chrome off >"$WORK/off-modified.log" 2>"$WORK/off-modified.err"; then
  echo "off removed a theme still selected by modified GTK settings" >&2
  exit 1
fi
grep -Fq 'user changed this after preview' "$GTK_SETTINGS"
grep -Fq 'user asset' "$GTK_THEME/gtk-3.0/gtk.css"
[[ -e $APP_STATE && -e $GTK_THEME && -e $STATE_DIR/backups/app-chrome-settings.ini ]]
grep -Fq 'ownership was retained' "$WORK/off-modified.err"

awk '{ if ($0 == "gtk-theme-name=One-Bit-Bureau-GTK3") print "gtk-theme-name=Adwaita"; else print }' "$GTK_SETTINGS" >"$GTK_SETTINGS.tmp"
mv "$GTK_SETTINGS.tmp" "$GTK_SETTINGS"
run app-chrome off >"$WORK/off-modified-away.log" 2>"$WORK/off-modified-away.err"
grep -Fq 'user changed this after preview' "$GTK_SETTINGS"
grep -Fq 'user asset' "$GTK_THEME/gtk-3.0/gtk.css"
[[ ! -e $APP_STATE ]]
grep -Fq 'preserved modified GTK settings' "$WORK/off-modified-away.err"
grep -Fq 'preserved modified GTK theme' "$WORK/off-modified-away.err"

echo "== doctor remains read-only and repair is explicit"
rm -rf "$GTK_THEME"
printf '%s\n' '[Settings]' 'gtk-theme-name=Adwaita' >"$GTK_SETTINGS"
before=$(shasum -a 256 "$GTK_SETTINGS" | awk '{print $1}')
run doctor >"$WORK/doctor.log"
[[ $(shasum -a 256 "$GTK_SETTINGS" | awk '{print $1}') == "$before" ]]
[[ ! -e $APP_STATE && ! -e $GTK_THEME ]]
grep -Fq 'doctor made no changes' "$WORK/doctor.log"
grep -Fq 'owned-theme alignment is unknown' "$WORK/doctor.log"
if grep -Fq 'owned theme link aligns' "$WORK/doctor.log"; then
  echo "doctor claimed owned-theme alignment from an incomplete state record" >&2
  exit 1
fi

run app-chrome on
run doctor --repair app-chrome-off >"$WORK/doctor-repair.log"
[[ $(<"$GTK_SETTINGS") == $'[Settings]\ngtk-theme-name=Adwaita' ]]
[[ ! -e $APP_STATE && ! -e $GTK_THEME ]]

echo "== off validates backup invariants before removing anything"
run app-chrome on
unlink "$STATE_DIR/backups/app-chrome-settings.ini"
if run app-chrome off >"$WORK/off-missing-backup.log" 2>"$WORK/off-missing-backup.err"; then
  echo "off accepted a missing settings backup" >&2
  exit 1
fi
[[ -e $APP_STATE && -e $GTK_THEME ]]
grep -Fq 'missing' "$WORK/off-missing-backup.err"
unlink "$APP_STATE"
rm -rf "$GTK_THEME"
printf '%s\n' '[Settings]' 'gtk-theme-name=Adwaita' >"$GTK_SETTINGS"

echo "== enable rollback leaves invalid UTF-8 settings untouched"
printf '\377\n' >"$GTK_SETTINGS"
before=$(shasum -a 256 "$GTK_SETTINGS" | awk '{print $1}')
if run app-chrome on >/dev/null 2>&1; then
  echo "on accepted invalid UTF-8 GTK settings" >&2
  exit 1
fi
[[ $(shasum -a 256 "$GTK_SETTINGS" | awk '{print $1}') == "$before" ]]
[[ ! -e $APP_STATE && ! -e $GTK_THEME && ! -e $STATE_DIR/backups/app-chrome-settings.ini ]]
printf '%s\n' '[Settings]' 'gtk-theme-name=Adwaita' >"$GTK_SETTINGS"

echo "== partial theme creation is self-cleaning"
PYTHONDONTWRITEBYTECODE=1 python3 - "$PLUGIN/scripts/one-bit-bureau-app-chrome.py" "$WORK/partial-theme" <<'PY'
import importlib.util
import sys
from pathlib import Path

source, root = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("app_chrome", source)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
index = root / "index.theme"
css = root / "gtk.css"
index.parent.mkdir(parents=True)
index.write_text("[Desktop Entry]\n", encoding="utf-8")
css.write_text("* {}\n", encoding="utf-8")
original = module.atomic_write
def fail_css(path, payload, mode=0o600):
    if path.name == "gtk.css":
        raise module.ChromeError("simulated CSS write failure")
    return original(path, payload, mode)
module.atomic_write = fail_css
destination = root / "One-Bit-Bureau-GTK3"
try:
    module.ensure_theme(index, css, destination)
except module.ChromeError:
    pass
else:
    raise SystemExit("ensure_theme accepted a simulated partial write")
assert not destination.exists()
PY

echo "== enable catches interruption-equivalent failures and rolls back"
PYTHONDONTWRITEBYTECODE=1 HOME="$HOME_DIR" python3 - "$PLUGIN/scripts/one-bit-bureau-app-chrome.py" "$PLUGIN" <<'PY'
import importlib.util
import os
import sys
from pathlib import Path

source, plugin = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("app_chrome_interrupt", source)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
location = module.paths(plugin)
settings = location["settings"]
original = settings.read_bytes()
original_ensure_theme = module.ensure_theme
def interrupt(*args, **kwargs):
    raise KeyboardInterrupt("simulated interruption")
module.ensure_theme = interrupt
try:
    module.turn_on(plugin)
except KeyboardInterrupt:
    pass
else:
    raise SystemExit("turn_on swallowed an interruption")
finally:
    module.ensure_theme = original_ensure_theme
assert settings.read_bytes() == original
assert not location["state"].exists()
assert not location["backup"].exists()
assert not location["theme"].exists()
PY

echo "== status rejects invalid backup invariants"
run app-chrome on
jq '.previousSettingsHash = "0000000000000000000000000000000000000000000000000000000000000000"' "$APP_STATE" >"$APP_STATE.tmp"
mv "$APP_STATE.tmp" "$APP_STATE"
if run app-chrome status >/dev/null 2>&1; then
  echo "status accepted an invalid previous-settings hash" >&2
  exit 1
fi
[[ -e $APP_STATE && -e $GTK_THEME && -e $STATE_DIR/backups/app-chrome-settings.ini ]]
unlink "$APP_STATE"
unlink "$STATE_DIR/backups/app-chrome-settings.ini"
rm -rf "$GTK_THEME"
printf '%s\n' '[Settings]' 'gtk-theme-name=Adwaita' >"$GTK_SETTINGS"

echo "== corrupt app-chrome state is rejected without mutation"
printf '%s\n' '{not json' >"$APP_STATE"
before=$(shasum -a 256 "$GTK_SETTINGS" | awk '{print $1}')
if run app-chrome status >/dev/null 2>&1; then
  echo "status accepted corrupt ownership state" >&2
  exit 1
fi
[[ $(shasum -a 256 "$GTK_SETTINGS" | awk '{print $1}') == "$before" ]]

echo "== doctor reports missing setup state without writing"
rm "$STATE_DIR/install-state.json"
before=$(shasum -a 256 "$GTK_SETTINGS" | awk '{print $1}')
run doctor >"$WORK/doctor-missing-state.log" 2>"$WORK/doctor-missing-state.err"
[[ $(shasum -a 256 "$GTK_SETTINGS" | awk '{print $1}') == "$before" ]]
grep -Fq 'setup ownership record is missing or unsafe' "$WORK/doctor-missing-state.log"

echo "diagnostics and app-chrome tests passed"
