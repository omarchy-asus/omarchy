#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin"
export CALL_LOG="$tmp_dir/calls"
real_udevadm=$(command -v udevadm || true)
export PATH="$tmp_dir/bin:$PATH"

cat >"$tmp_dir/bin/omarchy-hw-asus-rog" <<'SH'
#!/bin/bash
[[ ${IS_ROG:-1} == 1 ]]
SH
cat >"$tmp_dir/bin/omarchy-hw-match" <<'SH'
#!/bin/bash
[[ ${PRODUCT:-ROG Zephyrus G16 GA605KM_GA605KM} == *"$1"* ]]
SH
cat >"$tmp_dir/bin/sudo" <<'SH'
#!/bin/bash
echo "sudo $*" >>"$CALL_LOG"
"$@"
SH
chmod +x "$tmp_dir/bin/"*

leaf="$ROOT/install/hardware/asus/fix-asus-ga605km-touchpad-wake.sh"
migration="$ROOT/migrations/1792116410.sh"
rules="$tmp_dir/etc/udev/rules.d/99-omarchy-asus-ga605km-touchpad-wake.rules"
expected='ACTION=="add|bind", SUBSYSTEM=="i2c", KERNEL=="i2c-ASUF1209:*", ATTR{power/wakeup}="disabled"'

bash -n "$leaf" || fail "the hardware leaf has valid syntax"
grep -Fxq 'run_logged "$OMARCHY_INSTALL/hardware/asus/fix-asus-ga605km-touchpad-wake.sh"' "$ROOT/install/hardware/all.sh" &&
  pass "hardware setup runs the leaf" || fail "hardware setup runs the leaf"

run_leaf() {
  rm -rf "$tmp_dir/etc"
  OMARCHY_ASUS_TOUCHPAD_WAKE_RULES="$rules" bash -euo pipefail "$leaf" >/dev/null 2>&1
}

# The G16's i2c bus: the touchpad, armed, plus another device to leave alone.
write_devices() {
  rm -rf "$tmp_dir/i2c"
  mkdir -p "$tmp_dir/i2c/i2c-ASUF1209:00/power" "$tmp_dir/i2c/i2c-ELAN0001:00/power"
  echo "$1" >"$tmp_dir/i2c/i2c-ASUF1209:00/power/wakeup"
  echo enabled >"$tmp_dir/i2c/i2c-ELAN0001:00/power/wakeup"
}

run_migration() {
  : >"$CALL_LOG"
  OMARCHY_ASUS_TOUCHPAD_WAKE_RULES="$rules" OMARCHY_I2C_DEVICES_PATH="$tmp_dir/i2c" \
    bash -euo pipefail "$migration" >/dev/null 2>&1
}

IS_ROG=0 run_leaf
[[ ! -e $rules ]] && pass "new installs on other machines get no rule" || fail "new installs on other machines get no rule"

PRODUCT="ROG Zephyrus G14 GA403UV" run_leaf
[[ ! -e $rules ]] && pass "new installs on other ROG models get no rule" || fail "new installs on other ROG models get no rule"

run_leaf
grep -Fxq "$expected" "$rules" && pass "new installs on the GA605KM disarm the touchpad" || fail "new installs on the GA605KM disarm the touchpad"

rm -rf "$tmp_dir/etc"
write_devices enabled
IS_ROG=0 run_migration
[[ ! -e $rules && ! -s $CALL_LOG && $(<"$tmp_dir/i2c/i2c-ASUF1209:00/power/wakeup") == "enabled" ]] &&
  pass "the migration leaves other machines alone" || fail "the migration leaves other machines alone"

run_migration
grep -Fxq "$expected" "$rules" && pass "the migration installs the rule" || fail "the migration installs the rule"
[[ $(stat -c %a "$rules") == "644" ]] && pass "the rule is world-readable, root-writable" || fail "the rule is world-readable, root-writable"
[[ $(<"$tmp_dir/i2c/i2c-ASUF1209:00/power/wakeup") == "disabled" ]] &&
  pass "the running system stops waking on touch without a reboot" || fail "the running system stops waking on touch without a reboot"
[[ $(<"$tmp_dir/i2c/i2c-ELAN0001:00/power/wakeup") == "enabled" ]] &&
  pass "other i2c devices keep their wakeup" || fail "other i2c devices keep their wakeup"

run_migration
[[ ! -s $CALL_LOG ]] && pass "another user's run is a no-op" || fail "another user's run is a no-op" "$(cat "$CALL_LOG")"

echo '# administrator copy' >"$rules"
write_devices enabled
run_migration
grep -Fxq '# administrator copy' "$rules" && pass "an existing rule file is kept" || fail "an existing rule file is kept"

rm -rf "$tmp_dir/etc" "$tmp_dir/i2c"
mkdir -p "$tmp_dir/i2c"
run_migration && pass "a G16 whose touchpad is not enumerated still migrates" || fail "a G16 whose touchpad is not enumerated still migrates"

# New installs and the migration must write the same rule.
rule_from() { sed -n "/$2/,/^ *$3\$/p" "$1" | sed '1d;$d;s/^ *//'; }
leaf_rule=$(rule_from "$leaf" '"$rules" <<' RULES)
if [[ -n $leaf_rule && $leaf_rule == "$(rule_from "$migration" '"$rules" <<' RULES)" ]]; then
  pass "new installs and the migration write the same rule"
else
  fail "new installs and the migration write the same rule"
fi

if [[ -n $real_udevadm ]] && "$real_udevadm" verify --help >/dev/null 2>&1; then
  printf '%s\n' "$leaf_rule" >"$tmp_dir/99-omarchy-asus-ga605km-touchpad-wake.rules"
  "$real_udevadm" verify --no-summary "$tmp_dir/99-omarchy-asus-ga605km-touchpad-wake.rules" >/dev/null 2>&1 &&
    pass "udevadm verify accepts the rule" || fail "udevadm verify accepts the rule"
fi
