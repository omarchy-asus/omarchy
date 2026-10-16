#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin"

# lspci reads config space and wakes a runtime-suspended dGPU, so the answer
# must come from sysfs alone: a stub that fails loudly proves it is never run.
printf '#!/bin/bash\necho "lspci ran" >>"%s/lspci.log"\nexit 1\n' "$tmp_dir" >"$tmp_dir/bin/lspci"
chmod +x "$tmp_dir/bin/lspci"

export OMARCHY_PCI_DEVICES_PATH="$tmp_dir/devices" OMARCHY_DRI_BY_PATH="$tmp_dir/by-path"
export PATH="$tmp_dir/bin:$ROOT/bin:$PATH"

# Expected output ("-" for exit 1), render nodes present, then
# address=vendor:class[:boot_vga] for each display device.
while IFS='|' read -r description expected nodes devices; do
  rm -rf "$tmp_dir/devices" "$tmp_dir/by-path"
  mkdir -p "$tmp_dir/devices" "$tmp_dir/by-path"
  for address in $nodes; do
    : >"$tmp_dir/by-path/pci-$address-render"
  done
  for spec in $devices; do
    IFS=: read -r vendor class boot_vga <<<"${spec#*=}"
    device_dir="$tmp_dir/devices/${spec%%=*}"
    mkdir -p "$device_dir"
    printf '%s\n' "$vendor" >"$device_dir/vendor"
    printf '%s\n' "$class" >"$device_dir/class"
    if [[ -n $boot_vga ]]; then
      printf '%s\n' "$boot_vga" >"$device_dir/boot_vga"
    fi
  done

  status=0
  actual=$(omarchy-hw-igpu-render-node) || status=$?
  if [[ $expected == "-" ]]; then
    (( status == 1 )) && [[ -z $actual ]] || fail "$description" "expected exit 1, got $status: $actual"
  else
    [[ $actual == "$tmp_dir/by-path/pci-$expected-render" ]] || fail "$description" "expected $expected, got $status: $actual"
  fi
  pass "$description"
done <<'CASES'
Zephyrus G16: non-VGA AMD iGPU sorts after the RTX|0000:65:00.0|0000:64:00.0 0000:65:00.0|0000:64:00.0=0x10de:0x030000:0 0000:65:00.0=0x1002:0x038000
Intel iGPU claims boot_vga next to a 3D controller|0000:00:02.0|0000:00:02.0 0000:01:00.0|0000:00:02.0=0x8086:0x030000:1 0000:01:00.0=0x10de:0x030200
AMD iGPU claims boot_vga next to a VGA dGPU|0000:06:00.0|0000:01:00.0 0000:06:00.0|0000:01:00.0=0x10de:0x030000:0 0000:06:00.0=0x1002:0x030000:1
NVIDIA drives the display next to an inactive iGPU|-|0000:00:02.0 0000:01:00.0|0000:00:02.0=0x8086:0x030000:0 0000:01:00.0=0x10de:0x030000:1
No device claims boot_vga|-|0000:05:00.0 0000:01:00.0|0000:05:00.0=0x1002:0x030000 0000:01:00.0=0x10de:0x030200
AMD only|-|0000:65:00.0|0000:65:00.0=0x1002:0x038000
Intel only|-|0000:00:02.0|0000:00:02.0=0x8086:0x030000:1
NVIDIA only|-|0000:01:00.0|0000:01:00.0=0x10de:0x030000:1
Non-VGA AMD iGPU next to an NVIDIA 3D controller without boot_vga|-|0000:01:00.0 0000:65:00.0|0000:01:00.0=0x10de:0x030200 0000:65:00.0=0x1002:0x038000
iGPU without a render node|-|0000:64:00.0|0000:64:00.0=0x10de:0x030000:0 0000:65:00.0=0x1002:0x038000
CASES

[[ ! -e $tmp_dir/lspci.log ]] || fail "the render node comes from sysfs, never lspci"
pass "the render node comes from sysfs, never lspci"
