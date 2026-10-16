#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin"
export CALL_LOG="$tmp_dir/calls"
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

leaf="$ROOT/install/hardware/asus/fix-asus-ga605km-hibernate-mode.sh"
migration="$ROOT/migrations/1792129283.sh"
conf="$tmp_dir/etc/systemd/sleep.conf.d/omarchy-asus-ga605km-hibernate-mode.conf"

bash -n "$leaf" || fail "the hardware leaf has valid syntax"
grep -Fxq 'run_logged "$OMARCHY_INSTALL/hardware/asus/fix-asus-ga605km-hibernate-mode.sh"' "$ROOT/install/hardware/all.sh" &&
  pass "hardware setup runs the leaf" || fail "hardware setup runs the leaf"

run_leaf() {
  rm -rf "$tmp_dir/etc"
  OMARCHY_ASUS_HIBERNATE_MODE_CONF="$conf" bash -euo pipefail "$leaf" >/dev/null 2>&1
}

run_migration() {
  : >"$CALL_LOG"
  OMARCHY_ASUS_HIBERNATE_MODE_CONF="$conf" bash -euo pipefail "$migration" >/dev/null 2>&1
}

# The value systemd-sleep would use from the drop-in alone.
hibernate_mode() { sed -n 's/^HibernateMode=//p' "$conf"; }

IS_ROG=0 run_leaf
[[ ! -e $conf ]] && pass "new installs on other machines keep platform mode" || fail "new installs on other machines keep platform mode"

PRODUCT="ROG Zephyrus G14 GA403UV" run_leaf
[[ ! -e $conf ]] && pass "new installs on other ROG models keep platform mode" || fail "new installs on other ROG models keep platform mode"

run_leaf
[[ $(hibernate_mode) == "shutdown" ]] && grep -Fxq '[Sleep]' "$conf" &&
  pass "new installs on the GA605KM hibernate in shutdown mode" || fail "new installs on the GA605KM hibernate in shutdown mode"

rm -rf "$tmp_dir/etc"
IS_ROG=0 run_migration
[[ ! -e $conf && ! -s $CALL_LOG ]] && pass "the migration leaves other machines alone" || fail "the migration leaves other machines alone"

PRODUCT="ROG Zephyrus G14 GA403UV" run_migration
[[ ! -e $conf && ! -s $CALL_LOG ]] && pass "the migration leaves other ROG models alone" || fail "the migration leaves other ROG models alone"

run_migration
[[ $(hibernate_mode) == "shutdown" ]] && pass "the migration switches the GA605KM to shutdown mode" || fail "the migration switches the GA605KM to shutdown mode"
[[ $(stat -c %a "$conf") == "644" ]] && pass "the drop-in is world-readable, root-writable" || fail "the drop-in is world-readable, root-writable"

run_migration
[[ ! -s $CALL_LOG ]] && pass "another user's run is a no-op" || fail "another user's run is a no-op" "$(cat "$CALL_LOG")"

printf '[Sleep]\nHibernateMode=platform\n' >"$conf"
run_migration
[[ $(hibernate_mode) == "platform" ]] && pass "an administrator's drop-in is kept" || fail "an administrator's drop-in is kept"

# New installs and the migration must write the same drop-in.
conf_from() { sed -n "/$2/,/^ *$3\$/p" "$1" | sed '1d;$d;s/^ *//'; }
leaf_conf=$(conf_from "$leaf" '"$conf" <<' CONF)
if [[ -n $leaf_conf && $leaf_conf == "$(conf_from "$migration" '"$conf" <<' CONF)" ]]; then
  pass "new installs and the migration write the same drop-in"
else
  fail "new installs and the migration write the same drop-in"
fi
