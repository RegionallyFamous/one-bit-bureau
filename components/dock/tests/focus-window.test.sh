#!/bin/bash

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper="$root/scripts/focus-window"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"
printf '%s\n' '#!/bin/bash' >"$work/bin/hyprctl"
printf '%s\n' 'printf "%s\\n" "$*" >>"$HYPR_LOG"' >>"$work/bin/hyprctl"
printf '%s\n' 'if [[ $1 == "cursorpos" ]]; then echo "120, 340"; fi' >>"$work/bin/hyprctl"
printf '%s\n' 'if [[ $1 == "getoption" ]]; then printf "{\\\"int\\\":%s}\\n" "${NO_WARPS_INT:-1}"; fi' >>"$work/bin/hyprctl"
printf '%s\n' 'if [[ $1 == "dispatch" && $2 == *"hl.dsp.focus"* && ${FAIL_CURRENT_FOCUS:-0} == 1 ]]; then exit 1; fi' >>"$work/bin/hyprctl"
printf '%s\n' 'if [[ $1 == "dispatch" && $2 == "focuswindow" && ${FAIL_LEGACY_FOCUS:-0} == 1 ]]; then exit 1; fi' >>"$work/bin/hyprctl"
chmod +x "$work/bin/hyprctl"

export HYPR_LOG="$work/hyprctl.log"

if PATH="$work/bin:$PATH" bash "$helper" 'not-an-address' 2>/dev/null; then
  echo "focus helper accepted an invalid address" >&2
  exit 1
fi

PATH="$work/bin:$PATH" bash "$helper" '0xabc123'

grep -Fq 'eval hl.config({ cursor = { no_warps = true } })' "$HYPR_LOG"
grep -Fq 'dispatch hl.dsp.focus({ window = "address:0xabc123" })' "$HYPR_LOG"
grep -Fq 'dispatch hl.dsp.cursor.move({ x = 120, y = 340 })' "$HYPR_LOG"

restore_count=$(grep -Fc 'eval hl.config({ cursor = { no_warps = true } })' "$HYPR_LOG")
(( restore_count == 2 )) || {
  echo "focus helper did not restore the prior no_warps state" >&2
  exit 1
}

echo -n >"$HYPR_LOG"
NO_WARPS_INT=0 PATH="$work/bin:$PATH" bash "$helper" '0xdef456'
grep -Fq 'eval hl.config({ cursor = { no_warps = false } })' "$HYPR_LOG"
grep -Fq 'dispatch hl.dsp.cursor.move({ x = 120, y = 340 })' "$HYPR_LOG"

echo -n >"$HYPR_LOG"
FAIL_CURRENT_FOCUS=1 PATH="$work/bin:$PATH" bash "$helper" '0xfeed'
grep -Fq 'dispatch hl.dsp.focus({ window = "address:0xfeed" })' "$HYPR_LOG"
grep -Fq 'dispatch focuswindow address:0xfeed' "$HYPR_LOG"

echo -n >"$HYPR_LOG"
if NO_WARPS_INT=0 FAIL_CURRENT_FOCUS=1 FAIL_LEGACY_FOCUS=1 PATH="$work/bin:$PATH" bash "$helper" '0xfeed' 2>/dev/null; then
  echo "focus helper hid a focus failure" >&2
  exit 1
fi
grep -Fq 'eval hl.config({ cursor = { no_warps = false } })' "$HYPR_LOG"
grep -Fq 'dispatch hl.dsp.cursor.move({ x = 120, y = 340 })' "$HYPR_LOG"

echo "focus-window helper tests passed"
