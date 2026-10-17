#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

unit_dir=$(mktemp -d)
trap 'rm -rf "$unit_dir"' EXIT

dropin="$ROOT/default/systemd/system/nvidia-powerd.service.d/10-omarchy.conf"
[[ -f $dropin ]] || fail "the nvidia-powerd drop-in exists at $dropin"

mapfile -t lines < <(grep -vE '^[[:space:]]*(#|$)' "$dropin")
expected=("[Unit]" "StartLimitIntervalSec=60")
[[ ${lines[*]} == "${expected[*]}" ]] ||
  fail "the nvidia-powerd drop-in only bounds the start-limit window" "got: ${lines[*]}"
pass "the nvidia-powerd drop-in only bounds the start-limit window"

# The packaged unit restarts a crashed nvidia-powerd every 10 s and allows five
# starts. Those five crash restarts must still land inside the window, or the
# drop-in would let a crash loop run forever.
window=${lines[1]#StartLimitIntervalSec=}
(( 4 * 10 < window )) || fail "five crash restarts 10 s apart still trip the start limit" "window: ${window}s"
pass "five crash restarts 10 s apart still trip the start limit"

if command -v systemd-analyze >/dev/null; then
  mkdir -p "$unit_dir/nvidia-powerd.service.d"
  # The unit as nvidia-utils ships it.
  printf '%s\n' '[Unit]' 'Description=nvidia-powerd service' 'StartLimitIntervalSec=infinity' 'StartLimitBurst=5' \
    '[Service]' 'Type=simple' 'ExecStart=/usr/bin/true' 'Restart=on-failure' 'RestartSec=10' >"$unit_dir/nvidia-powerd.service"
  cp "$dropin" "$unit_dir/nvidia-powerd.service.d/"
  if output=$(SYSTEMD_UNIT_PATH="$unit_dir:" systemd-analyze verify --man=no "$unit_dir/nvidia-powerd.service" 2>&1); then
    [[ $output != *"Unknown"* && $output != *"Invalid"* ]] || fail "the nvidia-powerd drop-in parses cleanly" "$output"
    pass "the nvidia-powerd drop-in parses"
  elif [[ $output == *"Failed to initialize manager"* || $output == *"Access denied"* ]]; then
    printf 'ok - the nvidia-powerd drop-in parses # SKIP systemd-analyze cannot run here: %s\n' "${output%%$'\n'*}"
  else
    fail "the nvidia-powerd drop-in parses" "$output"
  fi
fi
