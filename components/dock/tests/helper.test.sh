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

echo "== missing pin state remains distinguishable from an explicitly empty dock"
python3 "$state_helper" read "$config/dock-icons.json" "$config/dock-pinned.json" "$config/dock-settings.json" | jq -e '.pins == {}' >/dev/null
printf '%s\n' '{"version":1,"pinned":[],"order":[]}' >"$config/dock-pinned.json"
python3 "$state_helper" read "$config/dock-icons.json" "$config/dock-pinned.json" "$config/dock-settings.json" | jq -e '.pins.pinned == []' >/dev/null
rm "$config/dock-pinned.json"

echo "== bundled pack roles are listed and associated offline"
HOME="$test_home" bash "$helper" pack list | grep -q '^terminal: Terminal$'
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
python3 "$state_helper" read "$config/dock-icons.json" "$config/dock-pinned.json" "$config/dock-settings.json" >"$work/exact.json"
jq -e '.icons.code == {"pack":"code"}' "$work/exact.json" >/dev/null
printf ' ' >>"$config/dock-icons.json"
python3 "$state_helper" read "$config/dock-icons.json" "$config/dock-pinned.json" "$config/dock-settings.json" >"$work/over.json"
jq -e '.icons == {}' "$work/over.json" >/dev/null

echo "== malformed, symlink, and FIFO inputs fail closed without blocking"
printf '{broken' >"$config/dock-icons.json"
python3 "$state_helper" read "$config/dock-icons.json" "$config/dock-pinned.json" "$config/dock-settings.json" | jq -e '.icons == {}' >/dev/null
printf '%s\n' '{"outside":{"pack":"games"}}' >"$work/outside.json"
rm "$config/dock-icons.json"
ln -s "$work/outside.json" "$config/dock-icons.json"
python3 "$state_helper" read "$config/dock-icons.json" "$config/dock-pinned.json" "$config/dock-settings.json" | jq -e '.icons == {}' >/dev/null
if HOME="$test_home" bash "$helper" pack set code files >"$work/symlink-write.log" 2>&1; then
  echo "mapping writer accepted a symlink" >&2
  exit 1
fi
grep -q 'outside' "$work/outside.json"
rm "$config/dock-icons.json"
mkfifo "$config/dock-icons.json"
python3 "$state_helper" read "$config/dock-icons.json" "$config/dock-pinned.json" "$config/dock-settings.json" | jq -e '.icons == {}' >/dev/null
rm "$config/dock-icons.json"

echo "== shaped state enforces record and multibyte field ceilings"
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
python3 "$state_helper" read "$config/dock-icons.json" "$config/dock-pinned.json" "$config/dock-settings.json" >"$work/shaped.json"
jq -e '(.icons | length) == 256 and (.pins.pinned | length) == 128 and .settings.autoHide == false' "$work/shaped.json" >/dev/null
python3 - "$work/shaped.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(data["settings"]["screenName"].encode("utf-8")) <= 160
PY

echo "== list emits only the shaped pinned set"
printf '%s\n' '{"code":{"pack":"terminal"}}' >"$config/dock-icons.json"
printf '%s\n' '{"pinned":["code"],"order":["code"]}' >"$config/dock-pinned.json"
HOME="$test_home" bash "$helper" list | grep -q '^code: One-Bit Bureau terminal$'

echo "== helper controller escalates deadline and unload cancellation to SIGKILL"
deadline_pid="$work/deadline-child.pid"
if python3 "$run_helper" 500 100 -- python3 -c 'import os, pathlib, signal, sys, time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)' "$deadline_pid" >"$work/deadline.log" 2>&1; then
  echo "deadline controller accepted a stalled helper" >&2
  exit 1
fi
grep -q 'helper exceeded its deadline' "$work/deadline.log"
[[ -s $deadline_pid ]]
if kill -0 "$(<"$deadline_pid")" 2>/dev/null; then
  echo "deadline controller left its TERM-ignoring child alive" >&2
  exit 1
fi

cancel_pid="$work/cancel-child.pid"
python3 "$run_helper" 10000 100 -- python3 -c 'import os, pathlib, signal, sys, time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)' "$cancel_pid" &
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
if kill -0 "$(<"$cancel_pid")" 2>/dev/null; then
  echo "cancelled controller left its TERM-ignoring child alive" >&2
  exit 1
fi

if [[ $(uname -s) == "Linux" ]]; then
  echo "== Linux parent-death gate contains SIGKILL before and after readiness"
  killed_pid="$work/killed-child.pid"
  python3 "$run_helper" 10000 100 -- python3 -c 'import os, pathlib, signal, sys, time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)' "$killed_pid" &
  killed_controller=$!
  for _ in {1..100}; do
    [[ -s $killed_pid ]] && break
    sleep 0.02
  done
  [[ -s $killed_pid ]]
  kill -KILL "$killed_controller"
  wait "$killed_controller" 2>/dev/null || true
  for _ in {1..100}; do
    ! kill -0 "$(<"$killed_pid")" 2>/dev/null && break
    sleep 0.02
  done
  ! kill -0 "$(<"$killed_pid")" 2>/dev/null || {
    echo "SIGKILLed controller left a ready child alive" >&2
    exit 1
  }

  pre_ready_pid="$work/pre-ready-task.pid"
  ONE_BIT_BUREAU_RUN_TEST_GATE_DELAY_MS=600 python3 "$run_helper" 10000 100 -- python3 -c 'import os, pathlib, sys, time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(60)' "$pre_ready_pid" &
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
  [[ -n $pre_ready_child ]]
  kill -KILL "$pre_ready_controller"
  wait "$pre_ready_controller" 2>/dev/null || true
  for _ in {1..150}; do
    ! kill -0 "$pre_ready_child" 2>/dev/null && break
    sleep 0.02
  done
  ! kill -0 "$pre_ready_child" 2>/dev/null || {
    echo "SIGKILLed controller left a pre-ready child alive" >&2
    exit 1
  }
  [[ ! -e $pre_ready_pid ]] || {
    echo "pre-ready task executed without its containment owner" >&2
    exit 1
  }
fi

echo "helper tests passed"
