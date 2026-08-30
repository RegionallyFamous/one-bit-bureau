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
bash -n "$ROOT/setup" "$ROOT/uninstall" "$ROOT/update" "$ROOT/one-bit-bureau" "$ROOT/test/omarchy-acceptance.sh" "$ROOT/shortlink/src/install.sh" "$ROOT/shortlink/test/install-test.sh"
bash "$ROOT/tests/install-roundtrip.sh"
bash "$ROOT/tests/update-ownership.sh"
bash "$ROOT/tests/coordinator-motion.sh"
bash "$ROOT/shortlink/test/install-test.sh"
bash -n "$ROOT/components/overview/activate-window" "$ROOT/components/dock/scripts/one-bit-bureau-icon" "$ROOT/components/dock/scripts/focus-window"
for dock_helper in "$ROOT/components/dock/scripts/one-bit-bureau-state" "$ROOT/components/dock/scripts/one-bit-bureau-run" "$ROOT/test/stubborn-state-helper.py"; do
  python3 -c 'import pathlib, sys; compile(pathlib.Path(sys.argv[1]).read_text(), sys.argv[1], "exec")' "$dock_helper"
done
for helper in "$ROOT/components/desktop/bin/common.py" "$ROOT/components/desktop/bin/desktop_policy.py" "$ROOT/components/desktop/bin/desktop-index" "$ROOT/components/desktop/bin/add-to-desktop"; do
  python3 -c 'import pathlib, sys; compile(pathlib.Path(sys.argv[1]).read_text(), sys.argv[1], "exec")' "$helper"
done
python3 -m unittest discover -s "$ROOT/components/desktop/tests" -p 'test_*.py'
python3 -m unittest discover -s "$ROOT/tests" -p 'test_*.py'
for artwork_helper in "$ROOT/artwork/render-bitmap-workbench.py" "$ROOT/artwork/render-crop-proof.py" "$ROOT/artwork/render-app-icons.py" "$ROOT/artwork/render-branding.py"; do
  python3 -c 'import pathlib, sys; compile(pathlib.Path(sys.argv[1]).read_text(), sys.argv[1], "exec")' "$artwork_helper"
done

[[ $(find "$ROOT/components/dock/assets/app-icons" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ') == 12 ]] || {
  echo "One-Bit Bureau app icon pack must contain exactly 12 rendered PNGs" >&2
  exit 1
}
jq -e '.schemaVersion == 1 and .id == "one-bit-bureau" and (.roles | length) == 12' "$ROOT/components/dock/assets/app-icons/pack.json" >/dev/null
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

for theme in "$ROOT"/themes/*; do
  [[ -f $theme/colors.toml ]] || continue
  python3 "$THEME_TOOL" validate --strict "$theme"
  proof_dir=$(mktemp -d "/tmp/$(basename "$theme").proof.XXXXXX")
  python3 "$THEME_TOOL" proof "$theme" --out "$proof_dir/proof.svg"
  render_path=$(mktemp -d "/tmp/$(basename "$theme").render.XXXXXX")
  python3 "$THEME_TOOL" render "$theme" --omarchy-root "$OMARCHY_ROOT" --out "$render_path"
done

echo "One-Bit Bureau static validation passed."
