#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export OMARCHY_PATH="$ROOT"
setup="$ROOT/install/hardware/asus/rog-winlock.sh"
migration="$ROOT/migrations/1792303756.sh"
rule="$scratch/etc/udev/rules.d/70-asus-rog-winlock.rules"
unit="$scratch/etc/systemd/user/omarchy-asus-rog-winlock.service"

# --- detector ---

mkdir -p "$scratch/bin"
cat >"$scratch/bin/omarchy-hw-asus-rog" <<'EOF'
#!/bin/bash
[[ $FAKE_ROG == "1" ]]
EOF
chmod +x "$scratch/bin/omarchy-hw-asus-rog"

usb_device() {
  mkdir -p "$scratch/sys/bus/usb/devices/$1"
  echo "$2" >"$scratch/sys/bus/usb/devices/$1/idVendor"
  echo "$3" >"$scratch/sys/bus/usb/devices/$1/idProduct"
}

detect() {
  PATH="$scratch/bin:$PATH" FAKE_ROG=$1 OMARCHY_SYS_ROOT="$scratch/sys" "$ROOT/bin/omarchy-hw-asus-rog-nkey"
}

usb_device 1-1 1d6b 0002
usb_device 1-2 0b05 1a30
detect 1 && fail "an ROG laptop without the N-Key Keyboard2 is not matched"
usb_device 3-5 0b05 19b6
detect 1 || fail "the N-Key Keyboard2 on an ROG laptop is matched"
detect 0 && fail "the keyboard alone, off an ROG laptop, is not matched"
pass "detector matches USB 0b05:19b6 on ASUS ROG laptops only"

# --- hardware setup and migration ---

# Exercise the real scripts, redirecting privileged writes to a temporary root.
omarchy-hw-asus-rog-nkey() { [[ $nkey == "1" ]]; }
sudo() {
  case "$1" in
    install) command install "$2" "$3" "$scratch$4" ;;
    systemctl) printf '%s\n' "$*" >>"$scratch/systemctl" ;;
    udevadm) printf '%s\n' "$*" >>"$scratch/udev" ;;
    *) fail "unexpected privileged command" "$*" ;;
  esac
}
systemctl() {
  [[ $1 == "--user" ]] || fail "unexpected systemctl call" "$*"
  printf '%s\n' "$*" >>"$scratch/user-systemctl"
  [[ $2 != "is-active" ]]
}

for entry in "$setup" "$migration"; do
  bash -n "$entry"
  for nkey in 1 0; do
    rm -rf "${scratch:?}/etc" "$scratch/systemctl" "$scratch/udev" "$scratch/user-systemctl"
    source "$entry"
    if [[ $nkey == "1" ]]; then
      cmp "$ROOT/default/udev/asus-rog-winlock.rules" "$rule" || fail "the hidraw access rule is installed"
      cmp "$ROOT/default/systemd/user/omarchy-asus-rog-winlock.service" "$unit" || fail "the user unit is installed"
      [[ $(stat -c %a "$rule") == "644" && $(stat -c %a "$unit") == "644" ]] || fail "installed files are not writable by other users"
      grep -Fxq 'systemctl --global enable omarchy-asus-rog-winlock.service' "$scratch/systemctl" || fail "the unit is enabled for every user"
      if [[ $entry == "$migration" ]]; then
        grep -Fxq 'udevadm trigger --action=change --subsystem-match=hidraw' "$scratch/udev" || fail "migration re-runs the hidraw rules"
        ! grep -q 'start' "$scratch/user-systemctl" || fail "migration does not start the unit outside a graphical session"
      else
        [[ ! -e $scratch/udev && ! -e $scratch/user-systemctl ]] || fail "installation does not contact the live udev daemon or user manager"
      fi
      source "$entry"
      cmp "$ROOT/default/udev/asus-rog-winlock.rules" "$rule" || fail "repeated setup preserves the rule"
    else
      [[ ! -e $scratch/etc && ! -e $scratch/systemctl && ! -e $scratch/udev && ! -e $scratch/user-systemctl ]] || fail "other hardware is untouched"
    fi
  done
done
pass "setup and migration are restricted to the N-Key keyboard and can be rerun"

# uaccess only takes effect when tagged before 73-seat-late.rules, and the
# input group is no fallback: Omarchy does not put users in it.
grep -Fq '/etc/udev/rules.d/70-' "$setup" || fail "the rule is installed ahead of 73-seat-late.rules"
access=$(sed '/^#/d; /^$/d' "$ROOT/default/udev/asus-rog-winlock.rules")
[[ $access == 'SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0b05", ATTRS{idProduct}=="19b6", TAG+="uaccess"' ]] || fail "access is limited to the keyboard's hidraw nodes via logind"
pass "hidraw access uses a scoped active-seat ACL"

grep -Fxq 'ExecStart=/usr/bin/omarchy-hw-asus-rog-winlock watch' "$ROOT/default/systemd/user/omarchy-asus-rog-winlock.service" || fail "the unit runs the watcher in its default toast mode"
pass "user unit watches in toast mode by default"

# --- helper ---

python3 - "$ROOT/bin/omarchy-hw-asus-rog-winlock" <<'EOF' || fail "the helper finds report 0x5d in a report descriptor"
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("winlock", sys.argv[1])
spec = importlib.util.spec_from_loader("winlock", loader)
winlock = importlib.util.module_from_spec(spec)
loader.exec_module(winlock)

# Usage Page (vendor), Usage, Collection, Report ID 0x5d, ..., End Collection.
vendor = bytes.fromhex("06 31 ff 09 76 a1 01 85 5d 19 00 2a ff 00 15 00 26 ff 00 75 08 95 3f b1 00 c0")
# A keyboard interface with Report ID 1, and a Usage of 0x85 followed by 0x5d data.
keyboard = bytes.fromhex("05 01 09 06 a1 01 85 01 09 85 5d c0")
# A long item whose data holds 85 5d must be skipped whole.
long_item = bytes.fromhex("fe 02 00 85 5d c0")
assert winlock.has_report_id(vendor, 0x5D)
assert not winlock.has_report_id(keyboard, 0x5D)
assert not winlock.has_report_id(long_item, 0x5D)
assert not winlock.has_report_id(b"\x85", 0x5D)
EOF
pass "helper picks the hidraw node whose descriptor carries report 0x5d"

grep -Fq '"input.superLocked"' "$ROOT/default/i18n/en/cli.json" || fail "OSD text is in the English catalog"
pass "OSD text comes from the catalog"
