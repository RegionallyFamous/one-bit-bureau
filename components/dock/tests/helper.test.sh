#!/bin/bash

set -euo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
helper="$root/scripts/one-bit-bureau-icon"
state_helper="$root/scripts/one-bit-bureau-state"
run_helper="$root/scripts/one-bit-bureau-run"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
test_home="$work/home"
config="$test_home/.config/omarchy/one-bit-bureau"
mkdir -p "$config"

state() {
  HOME="$test_home" python3 "$state_helper" "$@"
}

assert_dead() {
  local pid="$1" label="$2"
  for _ in {1..200}; do
    ! kill -0 "$pid" 2>/dev/null && return 0
    sleep 0.01
  done
  echo "$label remained alive: $pid" >&2
  return 1
}

echo "== missing pin state remains distinguishable from an explicitly empty dock"
state read dock | jq -e '.pins == {}' >/dev/null
printf '%s\n' '{"version":1,"pinned":[],"order":[]}' >"$config/dock-pinned.json"
state read dock | jq -e '.pins.pinned == []' >/dev/null
rm "$config/dock-pinned.json"

echo "== bundled pack roles are listed and associated offline"
HOME="$test_home" bash "$helper" pack list >"$work/pack-list.txt"
[[ $(wc -l <"$work/pack-list.txt" | tr -d ' ') == 32 ]]
grep -q '^application: Application$' "$work/pack-list.txt"
grep -q '^terminal: Terminal$' "$work/pack-list.txt"
HOME="$test_home" bash "$helper" pack set code terminal
jq -e '.code == {"pack":"terminal"}' "$config/dock-icons.json" >/dev/null

echo "== native, automatic, and clear are bounded mapping operations"
HOME="$test_home" bash "$helper" native code
jq -e '.code == {"mode":"native"}' "$config/dock-icons.json" >/dev/null
HOME="$test_home" bash "$helper" auto code
jq -e 'has("code") | not' "$config/dock-icons.json" >/dev/null
HOME="$test_home" bash "$helper" pack set code code
HOME="$test_home" bash "$helper" clear code
jq -e 'has("code") | not' "$config/dock-icons.json" >/dev/null

echo "== app IDs accept 160 ASCII bytes and reject 161"
id_160=$(printf '%160s' '' | tr ' ' a)
HOME="$test_home" bash "$helper" pack set "$id_160" files >/dev/null
HOME="$test_home" bash "$helper" auto "$id_160" >/dev/null
id_161="${id_160}a"
if HOME="$test_home" bash "$helper" pack set "$id_161" files >"$work/id-over.log" 2>&1; then
  echo "app ID accepted 161 bytes" >&2
  exit 1
fi

echo "== bounded reader accepts exactly 1 MiB and rejects one byte over"
python3 - "$config/dock-icons.json" <<'PY'
import json, sys
path = sys.argv[1]
raw = json.dumps({"code": {"pack": "code"}}, separators=(",", ":")).encode()
with open(path, "wb") as handle:
    handle.write(raw)
    handle.write(b" " * ((1024 * 1024) - len(raw)))
PY
state read dock >"$work/exact.json"
jq -e '.icons.code == {"pack":"code"}' "$work/exact.json" >/dev/null
printf ' ' >>"$config/dock-icons.json"
state read dock >"$work/over.json"
jq -e '.icons == {}' "$work/over.json" >/dev/null

echo "== malformed, symlink, hardlink, and FIFO inputs fail closed without blocking"
printf '{broken' >"$config/dock-icons.json"
state read dock | jq -e '.icons == {}' >/dev/null
printf '%s\n' '{"outside":{"pack":"games"}}' >"$work/outside.json"
rm "$config/dock-icons.json"
ln -s "$work/outside.json" "$config/dock-icons.json"
state read dock | jq -e '.icons == {}' >/dev/null
if HOME="$test_home" bash "$helper" pack set code files >"$work/symlink-write.log" 2>&1; then
  echo "mapping writer accepted a symlink" >&2
  exit 1
fi
grep -q 'outside' "$work/outside.json"
rm "$config/dock-icons.json"
ln "$work/outside.json" "$config/dock-icons.json"
state read dock | jq -e '.icons == {}' >/dev/null
rm "$config/dock-icons.json"
mkfifo "$config/dock-icons.json"
state read dock | jq -e '.icons == {}' >/dev/null
rm "$config/dock-icons.json"

echo "== state directory is private and cannot be replaced by a symlink"
state write settings '{"autoHide":true}'
if [[ $(uname -s) == "Darwin" ]]; then
  config_mode=$(stat -f '%Lp' "$config")
else
  config_mode=$(stat -c '%a' "$config")
fi
[[ $config_mode == 700 ]]
mv "$config" "$work/real-config"
ln -s "$work/real-config" "$config"
if state read dock >"$work/symlink-dir.log" 2>&1; then
  echo "state helper followed a replaced private directory" >&2
  exit 1
fi
rm "$config"
mv "$work/real-config" "$config"

echo "== shaped dock state enforces record and multibyte field ceilings"
python3 - "$config/dock-icons.json" "$config/dock-pinned.json" "$config/dock-settings.json" <<'PY'
import json, sys
icons, pins, settings = sys.argv[1:]
with open(icons, "w", encoding="utf-8") as handle:
    json.dump({f"app-{index}": {"pack": "files"} for index in range(257)}, handle)
with open(pins, "w", encoding="utf-8") as handle:
    json.dump({"pinned": [f"app-{index}" for index in range(129)], "order": []}, handle)
with open(settings, "w", encoding="utf-8") as handle:
    json.dump({"autoHide": False, "screenName": "é" * 81}, handle)
PY
state read dock >"$work/shaped.json"
jq -e '(.icons | length) == 256 and (.pins.pinned | length) == 128 and .settings.autoHide == false' "$work/shaped.json" >/dev/null
python3 - "$work/shaped.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(data["settings"]["screenName"].encode("utf-8")) <= 160
PY

echo "== positions enforce byte, key, record, depth, and coordinate ceilings"
state write positions '{"DP-1":{"file":{"x":1,"y":2}}}'
state read positions | jq -e '."DP-1".file == {"x":1,"y":2}' >/dev/null
if state write positions '{"DP-1":{"file":{"x":1,"y":2,"z":3}}}' >"$work/depth.log" 2>&1; then
  echo "positions accepted extra nesting" >&2
  exit 1
fi
python3 - "$config/desktop-icon-positions.json" <<'PY'
import json, sys
json.dump({f"screen-{index}": {} for index in range(17)}, open(sys.argv[1], "w"))
PY
state read positions | jq -e '. == {}' >/dev/null
if state write positions "$(python3 - <<'PY'
import json
print(json.dumps({"screen": {"é" * 128: {"x": 1, "y": 2}}}, ensure_ascii=False))
PY
)" >"$work/key-over.log" 2>&1; then
  echo "positions accepted a 256-byte item key" >&2
  exit 1
fi

echo "== list emits only the shaped pinned set"
printf '%s\n' '{"code":{"pack":"terminal"}}' >"$config/dock-icons.json"
printf '%s\n' '{"pinned":["code"],"order":["code"]}' >"$config/dock-pinned.json"
HOME="$test_home" bash "$helper" list | grep -q '^code: One-Bit Bureau terminal$'

echo "== helper controller enforces exact stdout/stderr byte ceilings without partial output"
python3 "$run_helper" 1000 100 4 4 -- python3 -c 'import sys; sys.stdout.buffer.write(b"1234"); sys.stderr.buffer.write(b"abcd")' >"$work/streams.out" 2>"$work/streams.err"
[[ $(<"$work/streams.out") == 1234 ]]
[[ $(<"$work/streams.err") == abcd ]]
if python3 "$run_helper" 1000 100 4 128 -- python3 -c 'print("12345", end="")' >"$work/over-output.out" 2>"$work/over-output.err"; then
  echo "controller accepted stdout one byte over" >&2
  exit 1
fi
[[ ! -s $work/over-output.out ]]
grep -q 'stdout exceeded its hard cap' "$work/over-output.err"
python3 "$run_helper" 1000 100 4 0 -- python3 -c 'print("éé", end="")' >"$work/multibyte.out"
[[ $(wc -c <"$work/multibyte.out" | tr -d ' ') == 4 ]]
if python3 "$run_helper" 1000 100 4 128 -- python3 -c 'print("ééé", end="")' >"$work/multibyte-over.out" 2>"$work/multibyte-over.err"; then
  echo "controller counted characters instead of bytes" >&2
  exit 1
fi
[[ ! -s $work/multibyte-over.out ]]

echo "== helper controller escalates deadline and cancellation to SIGKILL"
deadline_pid="$work/deadline-child.pid"
if python3 "$run_helper" 500 100 65536 65536 -- python3 -c 'import os, pathlib, signal, sys, time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)' "$deadline_pid" >"$work/deadline.log" 2>&1; then
  echo "deadline controller accepted a stalled helper" >&2
  exit 1
fi
grep -q 'helper exceeded its deadline' "$work/deadline.log"
assert_dead "$(<"$deadline_pid")" "deadline child"

cancel_pid="$work/cancel-child.pid"
python3 "$run_helper" 10000 100 65536 65536 -- python3 -c 'import os, pathlib, signal, sys, time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)' "$cancel_pid" &
controller_pid=$!
for _ in {1..100}; do
  [[ -s $cancel_pid ]] && break
  sleep 0.02
done
[[ -s $cancel_pid ]]
kill -TERM "$controller_pid"
if wait "$controller_pid"; then
  echo "cancelled controller returned success" >&2
  exit 1
else
  status=$?
  (( status == 143 )) || {
    echo "cancelled controller returned unexpected status $status" >&2
    exit 1
  }
fi
assert_dead "$(<"$cancel_pid")" "cancelled child"

if [[ $(uname -s) == "Linux" ]]; then
  echo "== Linux guardian reaps a TERM-ignoring nested process in a new session"
  nested_topology="$work/nested.json"
  if python3 "$run_helper" 600 100 65536 65536 -- python3 "$root/tests/process-topology-helper.py" "$nested_topology" >"$work/nested.log" 2>&1; then
    echo "nested process topology escaped the deadline" >&2
    exit 1
  fi
  jq -e '.parent.pid == .parent.pgid and .parent.pid == .parent.sid and .child.pid == .child.pgid and .child.pid == .child.sid and .child.ppid == .parent.pid' "$nested_topology" >/dev/null
  nested_parent=$(jq -r '.parent.pid' "$nested_topology")
  nested_child=$(jq -r '.child.pid' "$nested_topology")
  assert_dead "$nested_parent" "nested parent"
  assert_dead "$nested_child" "nested session child"

  echo "== Linux guardian survives controller SIGKILL and cleans before and after readiness"
  killed_pid="$work/killed-child.pid"
  python3 "$run_helper" 10000 100 65536 65536 -- python3 -c 'import os, pathlib, signal, sys, time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)' "$killed_pid" &
  killed_controller=$!
  for _ in {1..100}; do
    [[ -s $killed_pid ]] && break
    sleep 0.02
  done
  [[ -s $killed_pid ]]
  kill -KILL "$killed_controller"
  wait "$killed_controller" 2>/dev/null || true
  assert_dead "$(<"$killed_pid")" "ready child after controller death"

  pre_ready_pid="$work/pre-ready-task.pid"
  ONE_BIT_BUREAU_RUN_TEST_GATE_DELAY_MS=600 python3 "$run_helper" 10000 100 65536 65536 -- python3 -c 'import os, pathlib, sys, time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(60)' "$pre_ready_pid" &
  pre_ready_controller=$!
  sleep 0.08
  kill -KILL "$pre_ready_controller"
  wait "$pre_ready_controller" 2>/dev/null || true
  sleep 0.8
  [[ ! -e $pre_ready_pid ]] || {
    echo "pre-ready task executed after its controller died" >&2
    exit 1
  }
fi

echo "helper tests passed"
