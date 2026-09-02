#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OMARCHY_ROOT=$(cd -- "$ROOT/../.." && pwd)
THEME_TOOL="${OMARCHY_THEME_TOOL:-$HOME/.codex/skills/build-omarchy-themes/scripts/omarchy_theme.py}"

sha256() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

[[ -f $THEME_TOOL ]] || {
  echo "Theme authoring tool not found; set OMARCHY_THEME_TOOL to omarchy_theme.py" >&2
  exit 1
}

"$OMARCHY_ROOT/bin/omarchy-plugin-validate" "$ROOT"
bash -n "$ROOT/setup" "$ROOT/uninstall" "$ROOT/update" "$ROOT/one-bit-bureau" "$ROOT/test/omarchy-acceptance.sh" "$ROOT/release/install" "$ROOT/scripts/build-release-artifact" "$ROOT/shortlink/test/install-test.sh" "$ROOT/scripts/one-bit-bureau-doctor"
bash "$ROOT/tests/install-roundtrip.sh"
bash "$ROOT/tests/update-ownership.sh"
bash "$ROOT/tests/coordinator-motion.sh"
bash "$ROOT/tests/diagnostics-app-chrome.sh"
bash "$ROOT/shortlink/test/install-test.sh"
bash -n "$ROOT/components/overview/activate-window" "$ROOT/components/overview/move-window-to-workspace" "$ROOT/components/dock/scripts/one-bit-bureau-icon" "$ROOT/components/dock/scripts/focus-window"
for dock_helper in "$ROOT/components/dock/scripts/one-bit-bureau-state" "$ROOT/components/dock/scripts/one-bit-bureau-run" "$ROOT/test/stubborn-state-helper.py"; do
  python3 -c 'import pathlib, sys; compile(pathlib.Path(sys.argv[1]).read_text(), sys.argv[1], "exec")' "$dock_helper"
done
for helper in "$ROOT/components/desktop/bin/common.py" "$ROOT/components/desktop/bin/desktop_policy.py" "$ROOT/components/desktop/bin/desktop-index" "$ROOT/components/desktop/bin/add-to-desktop" "$ROOT/components/desktop/bin/desktop-operation" "$ROOT/components/desktop/bin/desktop-quick-look"; do
  python3 -c 'import pathlib, sys; compile(pathlib.Path(sys.argv[1]).read_text(), sys.argv[1], "exec")' "$helper"
done
for helper in "$ROOT/scripts/one-bit-bureau-app-chrome.py" "$ROOT/scripts/one_bit_bureau_secure_io.py"; do
  python3 -c 'import pathlib, sys; compile(pathlib.Path(sys.argv[1]).read_text(), sys.argv[1], "exec")' "$helper"
done
python3 -m unittest discover -s "$ROOT/components/desktop/tests" -p 'test_*.py'
python3 -m unittest discover -s "$ROOT/tests" -p 'test_*.py'
jq -e '
  .version == 1 and
  (.entries | type == "array" and length >= 6) and
  (.cases | type == "array" and length >= 10) and
  ([.cases[].name] | length == (unique | length)) and
  ([.cases[].family] | unique | length >= 8) and
  all(.cases[]; (.input | type == "object") and (.expected.id | type == "string") and (.expected.method | type == "string") and (.expected.ambiguous | type == "boolean"))
' "$ROOT/test/application-identity-fixtures.json" >/dev/null
node - "$ROOT" "$ROOT/test/application-identity-fixtures.json" <<'NODE'
const fs = require("node:fs")
const vm = require("node:vm")

const root = process.argv[2]
const fixturePath = process.argv[3]
const sourcePath = `${root}/components/dock/ApplicationIdentity.js`
const source = fs.readFileSync(sourcePath, "utf8").replace(/^\.pragma library\s*/, "")
const context = { module: { exports: {} }, console }
vm.runInNewContext(source, context, { filename: sourcePath })
const resolver = context.module.exports
const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8"))

for (const testCase of fixture.cases) {
  const actual = resolver.resolve(testCase.input, fixture.entries, [])
  for (const key of ["id", "method", "ambiguous"]) {
    if (actual[key] !== testCase.expected[key]) {
      throw new Error(`${testCase.name}: expected ${key}=${JSON.stringify(testCase.expected[key])}, got ${JSON.stringify(actual[key])}`)
    }
  }
}
NODE
python3 - "$ROOT" <<'PY'
import hashlib
import pathlib
import struct
import sys

root = pathlib.Path(sys.argv[1])
backgrounds = sorted((root / "themes/one-bit-bureau/backgrounds").glob("*.png"))
if [path.name for path in backgrounds] != [
    "one-bit-bureau-cleared-shift.png",
    "one-bit-bureau.png",
]:
    raise SystemExit("the release must contain exactly the two named wallpaper-family members")

hashes = set()
for path in backgrounds:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise SystemExit(f"{path.name}: not a bounded PNG wallpaper")
    width, height = struct.unpack(">II", data[16:24])
    if (width, height) != (3840, 2160):
        raise SystemExit(f"{path.name}: expected 3840x2160, got {width}x{height}")
    hashes.add(hashlib.sha256(data).hexdigest())
if len(hashes) != len(backgrounds):
    raise SystemExit("the second wallpaper must not duplicate the first")

proof = root / "docs/wallpaper-cleared-shift-crop-proof.png"
if not proof.is_file() or proof.stat().st_size < 1024:
    raise SystemExit("the second wallpaper needs a real crop-safety proof")
PY
python3 - "$ROOT" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
service = (root / "components/desktop/Service.qml").read_text(encoding="utf-8")
bar = (root / "components/active-window/BarWidget.qml").read_text(encoding="utf-8")
desk_start = service.find("  function deskMenuEntries() {")
desk_end = service.find("\n  function publishRouteState", desk_start)
desk_menu = service[desk_start:desk_end]
if desk_start < 0 or desk_end < 0:
    raise SystemExit("the stable Desk menu model is missing")

desk_rows = [
    'action: "folder", label: "New Folder"',
    'action: "quick-look", label: "Quick Look"',
    'action: "inspect", label: "Get Info"',
    'action: "rename", label: "Rename"',
    'action: "tidy", label: "Tidy Desk"',
    'action: "arrange-heading", label: "Arrange By", enabled: false',
    'action: "arrange-name", label: "  Name"',
    'action: "arrange-kind", label: "  Kind"',
    'action: "arrange-modified", label: "  Modified"',
    'action: "undo-layout", label: "Undo Desk Layout"',
    'action: "trash-selected", label: "Move to Trash"',
]
offsets = [desk_menu.find(row) for row in desk_rows]
if any(offset < 0 for offset in offsets) or offsets != sorted(offsets):
    raise SystemExit("the Desk menu stable row order or disabled heading contract changed")
for contract in (
    "height: 44",
    "String(modelData.reason || \"Unavailable command\")",
    "function getDeskMenuCurrentAction(): string",
    "function getSelectedId(): string",
    "function getVisualIndex(itemId: string, screenName: string): int",
    "function getSelectionCount(): int",
    "event.key === Qt.Key_Space && event.modifiers === Qt.NoModifier",
    "event.key === Qt.Key_F2",
    "event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)",
    "function undoDeskLayout()",
):
    if contract not in service:
        raise SystemExit(f"desktop interaction contract missing: {contract}")
for contract in (
    'Accessible.name: "Open Desk menu"',
    '"regionallyfamous.one-bit-bureau.desktop", "toggleDeskMenu", root.widgetScreenName',
    "implicitHeight: barSize",
):
    if contract not in bar:
        raise SystemExit(f"top-bar Desk contract missing: {contract}")
PY
for artwork_helper in "$ROOT/artwork/render-bitmap-workbench.py" "$ROOT/artwork/render-crop-proof.py" "$ROOT/artwork/render-app-icons.py" "$ROOT/artwork/render-branding.py"; do
  python3 -c 'import pathlib, sys; compile(pathlib.Path(sys.argv[1]).read_text(), sys.argv[1], "exec")' "$artwork_helper"
done

[[ $(find "$ROOT/components/dock/assets/app-icons" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ') == 32 ]] || {
  echo "One-Bit Bureau app icon pack must contain exactly 32 rendered PNGs" >&2
  exit 1
}
[[ $(find "$ROOT/artwork/imagegen/app-icons" -maxdepth 1 -type f -name '*-source.png' ! -name '*-rejected-source.png' | wc -l | tr -d ' ') == 32 ]] || {
  echo "One-Bit Bureau app icon artwork must contain exactly 32 selected source PNGs" >&2
  exit 1
}
while IFS= read -r source_icon; do
  [[ $(identify -ping -format '%[channels]' "$source_icon") == *a* ]] || {
    echo "One-Bit Bureau source icon must have an alpha channel: $source_icon" >&2
    exit 1
  }
done < <(find "$ROOT/artwork/imagegen/app-icons" -maxdepth 1 -type f -name '*-source.png' ! -name '*-rejected-source.png' -print)
jq -e '
  .schemaVersion == 2 and
  .id == "one-bit-bureau" and
  .fallbackRole == "application" and
  (.roles | length) == 32 and
  (.freshInstallApps | length) == 36 and
  ([.roles[].id] | length == (unique | length)) and
  ([.freshInstallApps[].id] | length == (unique | length)) and
  ([.freshInstallApps[].role] - [.roles[].id] | length == 0)
' "$ROOT/components/dock/assets/app-icons/pack.json" >/dev/null
while IFS= read -r role; do
  [[ -f $ROOT/components/dock/assets/app-icons/$role.png ]] || {
    echo "One-Bit Bureau rendered icon is missing for role: $role" >&2
    exit 1
  }
done < <(jq -r '.roles[].id' "$ROOT/components/dock/assets/app-icons/pack.json")
[[ $(identify -ping -format '%wx%h' "$ROOT/docs/assets/proof-photo.png") == "256x192" ]]
[[ $(identify -ping -format '%wx%h' "$ROOT/themes/one-bit-bureau/preview-unlock.png") == "1920x1080" ]]
[[ $(identify -ping -format '%[channels]' "$ROOT/themes/one-bit-bureau/unlock.png") == *a* ]]
[[ $(fc-scan --format '%{family[0]}' "$ROOT/fonts/DepartureMono-1.500.otf") == "Departure Mono" ]]
[[ $(fc-scan --format '%{family[0]}' "$ROOT/fonts/MonaspaceKryptonNF-Regular-1.400.otf") == "Monaspace Krypton NF" ]]
[[ $(sha256 "$ROOT/fonts/DepartureMono-1.500.otf") == "4d53f663155cf8bf7ffc8e688776e719625f7bbb80a8d90073438b249261a2e0" ]]
[[ $(sha256 "$ROOT/fonts/MonaspaceKryptonNF-Regular-1.400.otf") == "e4f4ce9b02139544d20c46eaa0ae7df9cce7bfcdcdeb75bb70575236ccc86954" ]]
[[ -s $ROOT/branding/about.txt && -s $ROOT/branding/screensaver.txt ]]

unsafe=$(find -P "$ROOT" -path "$ROOT/.git" -prune -o \( -type l -o -type f -perm -111 \) -print -quit)
if [[ -n $unsafe ]]; then
  echo "Unsafe theme-source payload: $unsafe" >&2
  exit 1
fi

if rg -n 'henri\.desktop-icons|crmne\.active-window|expose\.window-overview|omarchy-shell -q macos\.dock' "$ROOT/components" -g '*.qml' -g '*.js' -g '*.py' -g '*.sh'; then
  echo "Found a legacy plugin identity in runtime code" >&2
  exit 1
fi

former_first="$(printf '%s' 'pap' 'er')[-_ ]?$(printf '%s' 'j' 'am')"
former_second=$(printf '%s' 'alu' 'mina')
former_pattern="${former_first}|${former_second}"
if rg -n -i "$former_pattern" "$ROOT" --hidden --glob '!.git' --glob '!.git/**'; then
  echo "Found a former product identity in repository content" >&2
  exit 1
fi

former_path=$(
  while IFS= read -r candidate; do
    relative=${candidate#"$ROOT/"}
    lowercase=${relative,,}
    if [[ $lowercase =~ $former_pattern ]]; then
      printf '%s\n' "$relative"
      break
    fi
  done < <(find "$ROOT" -mindepth 1 -path "$ROOT/.git" -prune -o -print)
)
if [[ -n $former_path ]]; then
  echo "Found a former product identity in repository path: $former_path" >&2
  exit 1
fi

(
  cd "$ROOT/components/dock"
  bash tests/run.sh
)

bash "$ROOT/components/inspector/tests/run.sh"
bash "$ROOT/components/overview/tests/run.sh"

for theme in "$ROOT"/themes/*; do
  [[ -f $theme/colors.toml ]] || continue
  python3 "$THEME_TOOL" validate --strict "$theme"
  proof_dir=$(mktemp -d "/tmp/$(basename "$theme").proof.XXXXXX")
  python3 "$THEME_TOOL" proof "$theme" --out "$proof_dir/proof.svg"
  render_path=$(mktemp -d "/tmp/$(basename "$theme").render.XXXXXX")
  python3 "$THEME_TOOL" render "$theme" --omarchy-root "$OMARCHY_ROOT" --out "$render_path"
done

echo "One-Bit Bureau static validation passed."
