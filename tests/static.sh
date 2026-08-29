#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OMARCHY_ROOT=$(cd -- "$ROOT/../.." && pwd)
THEME_TOOL="${OMARCHY_THEME_TOOL:-$HOME/.codex/skills/build-omarchy-themes/scripts/omarchy_theme.py}"

[[ -f $THEME_TOOL ]] || {
  echo "Theme authoring tool not found; set OMARCHY_THEME_TOOL to omarchy_theme.py" >&2
  exit 1
}

"$OMARCHY_ROOT/bin/omarchy-plugin-validate" "$ROOT"
bash -n "$ROOT/setup" "$ROOT/uninstall" "$ROOT/test/omarchy-acceptance.sh"
bash -n "$ROOT/components/overview/activate-window" "$ROOT/components/overview/background-blur-session" "$ROOT/components/dock/scripts/omarchy-dock-icon"
for helper in "$ROOT/components/desktop/bin/common.py" "$ROOT/components/desktop/bin/desktop-index" "$ROOT/components/desktop/bin/add-to-desktop"; do
  python3 -c 'import pathlib, sys; compile(pathlib.Path(sys.argv[1]).read_text(), sys.argv[1], "exec")' "$helper"
done
for artwork_helper in "$ROOT/artwork/render-bitmap-workbench.py" "$ROOT/artwork/render-crop-proof.py"; do
  python3 -c 'import pathlib, sys; compile(pathlib.Path(sys.argv[1]).read_text(), sys.argv[1], "exec")' "$artwork_helper"
done

unsafe=$(find -P "$ROOT" -path "$ROOT/.git" -prune -o \( -type l -o -type f -perm -111 \) -print -quit)
if [[ -n $unsafe ]]; then
  echo "Unsafe theme-source payload: $unsafe" >&2
  exit 1
fi

if rg -n 'henri\.desktop-icons|crmne\.active-window|expose\.window-overview|omarchy-shell -q macos\.dock' "$ROOT/components" -g '*.qml' -g '*.js' -g '*.py' -g '*.sh'; then
  echo "Found a legacy plugin identity in runtime code" >&2
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

echo "Alumina Raster static validation passed."
