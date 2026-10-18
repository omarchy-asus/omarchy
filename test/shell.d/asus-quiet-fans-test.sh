#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

helper="$ROOT/bin/omarchy-powerprofiles-asus-quiet-fans"
sudoers_file="$ROOT/etc/sudoers.d/omarchy-asus-quiet-fans"
rule='%wheel ALL=(root) NOPASSWD: /usr/bin/omarchy-powerprofiles-asus-quiet-fans on, /usr/bin/omarchy-powerprofiles-asus-quiet-fans off'

# Exactly the two whole commands. Dropping the arguments, which sudoers reads
# as "any arguments", would let the grant carry anything the helper accepts
# later.
rules=$(grep -vE '^[[:space:]]*(#|$)' "$sudoers_file")
[[ $rules == "$rule" ]] ||
  fail "quiet fans sudoers file carries exactly the on and off rule" "got: $rules"
if command -v visudo >/dev/null; then
  visudo -cf "$sudoers_file" >/dev/null || fail "quiet fans sudoers rule parses"
fi
grep -Fx 'PACKAGED_PATH=/usr/bin/omarchy-powerprofiles-asus-quiet-fans' "$helper" >/dev/null ||
  fail "the helper elevates the path the sudoers rule names"
grep -F 'sudo -n "$PACKAGED_PATH" "$mode"' "$helper" >/dev/null ||
  fail "the helper takes the grant without prompting"
# Without the packaged helper or the grant (a dev-linked checkout) the fans are
# left alone, and the journal says why once per boot.
grep -F 'logger -t omarchy-powerprofiles-asus-quiet-fans' "$helper" >/dev/null &&
  grep -F 'omarchy-powerprofiles-asus-quiet-fans.skipped' "$helper" >/dev/null ||
  fail "a missing helper or grant is logged once instead of skipped silently"
gated=$(grep -A1 -E '^if \(\( EUID == 0 \)\); then$' "$helper" || true)
[[ $gated == *"export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin"* ]] ||
  fail "the helper pins PATH to system directories when it holds root"
if grep -E '^[^#]*\bomarchy-[a-z]' "$helper" | grep -v 'omarchy-powerprofiles-asus-quiet-fans' >/dev/null; then
  fail "the helper calls no other omarchy command, which root could resolve from a checkout"
fi
pass "the sudoers grant covers on and off of one packaged helper"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
# Toggle flags live under $HOME; keep the developer's own out of the test.
export HOME="$tmp_dir/home"
mkdir -p "$HOME"

sys="$tmp_dir/sys"
amd="$sys/class/platform-profile/platform-profile-0"
asus="$sys/class/platform-profile/platform-profile-1"
mkdir -p "$sys/class/dmi/id" "$amd" "$asus" "$sys/class/power_supply/ACAD" "$sys/class/power_supply/BAT1"
printf 'ROG Zephyrus G16 GA605KM_GA605KM\n' >"$sys/class/dmi/id/product_name"
printf 'amd-pmf\n' >"$amd/name"
printf 'asus-wmi\n' >"$asus/name"
printf 'Mains\n' >"$sys/class/power_supply/ACAD/type"
printf 'Battery\n' >"$sys/class/power_supply/BAT1/type"

state() {
  chmod u+w "$amd/profile" "$asus/profile" 2>/dev/null || true
  printf '%s\n' "$1" >"$asus/profile"
  printf '%s\n' "$2" >"$amd/profile"
  printf '%s\n' "$3" >"$sys/class/power_supply/ACAD/online"
}

# A write the helper should not make fails here, and the helper with it.
frozen() {
  chmod a-w "$amd/profile" "$asus/profile"
}

fans() {
  OMARCHY_SYS_ROOT="$sys" "$helper" "$@"
}

profiles() {
  printf '%s %s\n' "$(<"$asus/profile")" "$(<"$amd/profile")"
}

state balanced balanced 0
fans on
[[ $(profiles) == "quiet balanced" ]] || fail "on battery the ASUS handler goes quiet and the AMD one stays balanced" "got: $(profiles)"
frozen
fans on || fail "a second on writes nothing"
pass "on battery in balanced the fans go quiet once"

state balanced balanced 1
frozen
fans on || fail "on AC nothing is written"
state performance performance 0
frozen
fans on || fail "outside balanced nothing is written"
state quiet low-power 0
frozen
fans on || fail "the full quiet profile is left alone"
pass "quiet fans apply only on battery with both handlers balanced"

state quiet balanced 1
fans off
[[ $(profiles) == "balanced balanced" ]] || fail "off restores balanced" "got: $(profiles)"
frozen
fans off || fail "off from balanced writes nothing"
state performance performance 1
frozen
fans off || fail "off leaves a profile set by someone else alone"
pass "off undoes only the mixed quiet state"

state balanced balanced 0
printf 'ROG Zephyrus G14 GA403UV\n' >"$sys/class/dmi/id/product_name"
frozen
fans on || fail "another model is left alone"
printf 'ROG Zephyrus G16 GA605KM_GA605KM\n' >"$sys/class/dmi/id/product_name"
rm -r "$asus"
fans on || fail "a GA605KM without the ASUS handler is left alone"
pass "only a GA605KM with both handlers is touched"

for bad in "" quiet normal "on off" "../x" "on;id"; do
  if fans "$bad" >/dev/null 2>&1; then
    fail "the helper rejects '$bad'"
  fi
done
if fans on off >/dev/null 2>&1; then
  fail "the helper rejects more than one argument"
fi
pass "the helper accepts nothing but on or off"

# omarchy-powerprofiles-set picks on or off from the source and the profile.
mkdir -p "$tmp_dir/bin" "$tmp_dir/state"
cat >"$tmp_dir/bin/omarchy-hw-match" <<'EOF'
#!/bin/bash
[[ ${STUB_PRODUCT:-GA605KM} == *"$1"* ]]
EOF
cat >"$tmp_dir/bin/omarchy-hw-asus-rog-usbc-power" <<'EOF'
#!/bin/bash
exit 1
EOF
cat >"$tmp_dir/bin/omarchy-powerprofiles-asus-quiet-fans" <<'EOF'
#!/bin/bash
printf '%s\n' "$1" >>"$FANS_LOG"
EOF
cat >"$tmp_dir/bin/powerprofilesctl" <<'EOF'
#!/bin/bash
[[ $1 == "list" ]] && printf '  power-saver:\n* balanced:\n  performance:\n'
exit 0
EOF
chmod +x "$tmp_dir/bin/"*

set_profile() {
  : >"$tmp_dir/fans"
  FANS_LOG="$tmp_dir/fans" PATH="$tmp_dir/bin:$ROOT/bin:$PATH" \
    OMARCHY_POWERPROFILES_STATE_DIR="$tmp_dir/state" \
    "$ROOT/bin/omarchy-powerprofiles-set" "$@"
  cat "$tmp_dir/fans"
}

[[ $(set_profile battery) == "on" ]] || fail "battery in balanced turns quiet fans on"
[[ $(set_profile ac) == "off" ]] || fail "AC turns quiet fans off"
[[ $(set_profile battery power-saver) == "off" ]] || fail "power-saver on battery turns quiet fans off"
[[ $(STUB_PRODUCT=GA403UV set_profile battery balanced) == "" ]] || fail "other machines never call the helper"
pass "omarchy-powerprofiles-set turns quiet fans on only for balanced on battery on the GA605KM"
