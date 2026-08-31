#!/bin/bash

set -euo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HELPER="$TEST_DIR/../move-window-to-workspace"
FIXTURE=$(mktemp -d)
trap 'rm -rf -- "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/bin" "$FIXTURE/state"

cat >"$FIXTURE/bin/hyprctl" <<'STUB'
#!/bin/bash
set -euo pipefail

mode=${STUB_MODE:-confirmed}
address=${STUB_ADDRESS:-0xabc123}
pid=${STUB_PID:-4242}
workspace=${STUB_WORKSPACE:-4}
monitor=${STUB_MONITOR:-DP-1}
monitor_id=${STUB_MONITOR_ID:-7}
initial_class=${STUB_INITIAL_CLASS-org.example.App}
initial_title=${STUB_INITIAL_TITLE-Original window}
state_dir=${STUB_STATE_DIR:?}

if [[ ${1:-} == "-j" && ${2:-} == "monitors" ]]; then
  if [[ $mode == "vanished-output" ]]; then
    printf '[]\n'
  else
    jq -cn --arg monitor "$monitor" --argjson monitor_id "$monitor_id" \
      '[{id: $monitor_id, name: $monitor}]'
  fi
  exit 0
fi

if [[ ${1:-} == "-j" && ${2:-} == "workspaces" ]]; then
  if [[ $mode == "vanished-workspace" ]]; then
    printf '[]\n'
  else
    jq -cn --argjson workspace "$workspace" --arg monitor "$monitor" '[{id: $workspace, monitor: $monitor}]'
  fi
  exit 0
fi

if [[ ${1:-} == "-j" && ${2:-} == "clients" ]]; then
  client_pid=$pid
  if [[ $mode == "reused-address" ]]; then
    client_pid=$((pid + 1))
  fi
  client_initial_title=$initial_title
  if [[ $mode == "reused-fingerprint" ]]; then
    client_initial_title="Replacement window"
  fi
  client_workspace=1
  if [[ -f $state_dir/moved && $mode != "pending" ]]; then
    client_workspace=$workspace
  fi
  jq -cn --arg address "$address" --argjson pid "$client_pid" \
    --argjson workspace "$client_workspace" --arg monitor "$monitor" \
    --argjson monitor_id "$monitor_id" \
    --arg initial_class "$initial_class" --arg initial_title "$client_initial_title" \
    '[{address: $address, pid: $pid, initialClass: $initial_class, initialTitle: $initial_title, workspace: {id: $workspace}, monitor: $monitor_id}]'
  exit 0
fi

if [[ ${1:-} == "dispatch" ]]; then
  if [[ $mode == "dispatcher-refused" ]]; then
    exit 1
  fi
  if [[ ${2:-} == hl.dsp.window.move* && $mode == "fallback" ]]; then
    exit 1
  fi
  if [[ ${2:-} == hl.dsp.window.move* && $mode == "lua-noop" ]]; then
    exit 0
  fi
  printf '1\n' >"$state_dir/moved"
  exit 0
fi

exit 2
STUB
chmod +x "$FIXTURE/bin/hyprctl"

run_helper() {
  local mode=$1 address=$2 workspace=$3 pid=$4 monitor=$5
  local initial_class="org.example.App" initial_title="Original window"
  if (( $# >= 6 )); then
    initial_class=$6
  fi
  if (( $# >= 7 )); then
    initial_title=$7
  fi
  rm -f -- "$FIXTURE/state/moved"
  PATH="$FIXTURE/bin:$PATH" \
    STUB_MODE="$mode" \
    STUB_ADDRESS="${address,,}" \
    STUB_WORKSPACE="$workspace" \
    STUB_PID="$pid" \
    STUB_MONITOR="$monitor" \
    STUB_INITIAL_CLASS="$initial_class" \
    STUB_INITIAL_TITLE="$initial_title" \
    STUB_STATE_DIR="$FIXTURE/state" \
    bash "$HELPER" "$address" "$workspace" "$pid" "$monitor" "$initial_class" "$initial_title"
}

output=$(run_helper confirmed 0xABC123 4 4242 DP-1)
[[ $output == $'confirmed\tlua\t0xabc123\t4\tDP-1' ]]

set +e
PATH="$FIXTURE/bin:$PATH" bash "$HELPER" 0xABC123 4 >"$FIXTURE/out" 2>"$FIXTURE/error"
legacy_status=$?
set -e
[[ $legacy_status == 64 ]]
grep -Fq "invalid window identity" "$FIXTURE/error"

output=$(run_helper fallback 0xABC123 4 4242 DP-1)
[[ $output == $'confirmed\tlegacy\t0xabc123\t4\tDP-1' ]]

output=$(run_helper lua-noop 0xABC123 4 4242 DP-1)
[[ $output == $'confirmed\tlegacy\t0xabc123\t4\tDP-1' ]]

if run_helper reused-address 0xABC123 4 4242 DP-1 >"$FIXTURE/out" 2>"$FIXTURE/error"; then
  echo "reused address unexpectedly moved" >&2
  exit 1
fi
grep -Fq "window identity changed" "$FIXTURE/error"

if run_helper reused-fingerprint 0xABC123 4 4242 DP-1 >"$FIXTURE/out" 2>"$FIXTURE/error"; then
  echo "reused address fingerprint unexpectedly moved" >&2
  exit 1
fi
grep -Fq "window identity changed" "$FIXTURE/error"

if run_helper vanished-output 0xABC123 4 4242 DP-1 >"$FIXTURE/out" 2>"$FIXTURE/error"; then
  echo "vanished output unexpectedly accepted" >&2
  exit 1
fi
grep -Fq "display is no longer available" "$FIXTURE/error"

if run_helper vanished-workspace 0xABC123 4 4242 DP-1 >"$FIXTURE/out" 2>"$FIXTURE/error"; then
  echo "vanished workspace unexpectedly accepted" >&2
  exit 1
fi
grep -Fq "workspace is no longer available" "$FIXTURE/error"

set +e
output=$(run_helper pending 0xABC123 4 4242 DP-1)
status=$?
set -e
[[ $status == 75 ]]
[[ $output == $'pending\tlegacy\t0xabc123\t4\tDP-1' ]]

max_monitor=$(printf 'D%.0s' {1..128})
max_address="0x1234567890abcdef"
output=$(run_helper confirmed "$max_address" 999 4194304 "$max_monitor")
[[ $output == $'confirmed\tlua\t0x1234567890abcdef\t999\t'"$max_monitor" ]]

too_long_address="0x1234567890abcdef0"
if run_helper confirmed "$too_long_address" 999 4194304 "$max_monitor" >/dev/null 2>&1; then
  echo "17-digit address exceeded the ceiling" >&2
  exit 1
fi
if run_helper confirmed "$max_address" 1000 4194304 "$max_monitor" >/dev/null 2>&1; then
  echo "workspace 1000 exceeded the ceiling" >&2
  exit 1
fi
if run_helper confirmed "$max_address" 999 4194305 "$max_monitor" >/dev/null 2>&1; then
  echo "PID 4194305 exceeded the ceiling" >&2
  exit 1
fi
too_long_monitor="${max_monitor}D"
if run_helper confirmed "$max_address" 999 4194304 "$too_long_monitor" >/dev/null 2>&1; then
  echo "129-character monitor exceeded the ceiling" >&2
  exit 1
fi
max_identity=$(printf 'I%.0s' {1..256})
output=$(run_helper confirmed "$max_address" 999 4194304 "$max_monitor" "$max_identity" "")
[[ $output == $'confirmed\tlua\t0x1234567890abcdef\t999\t'"$max_monitor" ]]
too_long_identity="${max_identity}I"
if run_helper confirmed "$max_address" 999 4194304 "$max_monitor" "$too_long_identity" "" >/dev/null 2>&1; then
  echo "257-character window fingerprint exceeded the ceiling" >&2
  exit 1
fi

printf 'workspace move helper tests passed\n'
