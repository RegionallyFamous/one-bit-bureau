#!/bin/bash
set -euo pipefail

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

helper="$(pwd)/scripts/application-identity-metadata"
data_home="$tmp_dir/home-data"
data_system="$tmp_dir/system-data"
mkdir -p "$data_home/applications/nested" "$data_system/applications" "$tmp_dir/proc/4242"

printf '%s\n' \
  '[Desktop Entry]' \
  'Type=Application' \
  'Name=Code' \
  'StartupWMClass=Code' \
  'X-Flatpak=com.visualstudio.code' \
  'Exec=flatpak run com.visualstudio.code --new-window' \
  > "$data_home/applications/nested/com.visualstudio.code.desktop"

printf '%s\n' \
  '[Desktop Entry]' \
  'Type=Application' \
  'Name=Ignored lower-precedence duplicate' \
  'StartupWMClass=WrongClass' \
  'Exec=wrong-code' \
  > "$data_system/applications/nested-com.visualstudio.code.desktop"

desktop_json=$(XDG_DATA_HOME="$data_home" XDG_DATA_DIRS="$data_system" python3 "$helper" desktop-index)
python3 - "$desktop_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["version"] == 1
entry = payload["entries"]["nested-com.visualstudio.code"]
assert entry["startupWmClass"] == "Code"
assert entry["aliases"] == ["com.visualstudio.code"]
assert entry["processNames"] == ["flatpak", "com.visualstudio.code"]
assert len(json.dumps(payload).encode()) <= 1024 * 1024
PY

printf 'code\n' > "$tmp_dir/proc/4242/comm"
printf '/usr/bin/code\0--unity-launch\0' > "$tmp_dir/proc/4242/cmdline"
printf '4242 (code helper) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 987654 20\n' \
  > "$tmp_dir/proc/4242/stat"
ln -s /usr/bin/code "$tmp_dir/proc/4242/exe"

process_json=$(ONE_BIT_BUREAU_PROC_ROOT="$tmp_dir/proc" python3 "$helper" process 0xABC=4242)
python3 - "$process_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
record = payload["processes"]["0xabc"]
assert record["pid"] == 4242
assert record["processName"] == "code"
assert record["executable"] == "/usr/bin/code"
assert record["identityNames"] == ["code"]
assert len(record["argv"]) == 2
PY

if python3 "$helper" process invalid >/dev/null 2>&1; then
  echo "expected malformed address/PID input to fail" >&2
  exit 1
fi

too_many=()
for index in $(seq 1 65); do
  too_many+=("0x$(printf '%x' "$index")=$index")
done
if python3 "$helper" process "${too_many[@]}" >/dev/null 2>&1; then
  echo "expected the 64-process ceiling to reject input 65" >&2
  exit 1
fi

echo "application identity metadata tests passed"
