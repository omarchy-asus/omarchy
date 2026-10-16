#!/bin/bash
#
# On ASUS ROG laptops the soft mixer leaves the ALC285 hardware Master where
# install set it, so install must set it to full scale. The migration must never
# change the level on an existing install: it only tells installs still at the
# old 80% how to raise it, once, and stays silent everywhere else.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

leaf="$ROOT/install/user/hardware/asus/fix-audio-mixer.sh"
migration="$ROOT/migrations/1792162887.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

stub_bin="$test_dir/bin"
calls="$test_dir/calls"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-hw-asus-rog" <<'STUB'
#!/bin/bash
[[ ${IS_ROG:-1} == 1 ]]
STUB
cat >"$stub_bin/aplay" <<'STUB'
#!/bin/bash
[[ ${HAS_ALC285:-1} == 1 ]] && echo "card 2: Generic_1 [HD-Audio Generic], device 0: ALC285 Analog [ALC285 Analog]"
exit 0
STUB
cat >"$stub_bin/omarchy-notification-send" <<'STUB'
#!/bin/bash
printf 'notify %s\n' "$*" >>"$CALLS"
STUB
cat >"$stub_bin/amixer" <<'STUB'
#!/bin/bash
printf 'amixer %s\n' "$*" >>"$CALLS"
if [[ $* == *"sget Master"* ]]; then
  echo "Simple mixer control 'Master',0"
  echo "  Mono: Playback ${MASTER:-70 [80%] [-12.75dB] [on]}"
fi
exit 0
STUB
chmod +x "$stub_bin"/*

soft_mixer="$test_dir/home/.config/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf"
mkdir -p "$(dirname "$soft_mixer")"
touch "$soft_mixer"

run() {
  local script="$1"
  shift
  rm -f "$calls"
  touch "$calls"
  env HOME="$test_dir/home" OMARCHY_PATH="$ROOT" CALLS="$calls" PATH="$stub_bin:$PATH" "$@" \
    bash -euo pipefail "$script" >"$test_dir/out" 2>&1
}

run "$leaf" || fail "install leaf succeeds on a ROG with an ALC285"
grep -qx 'amixer -c 2 set Master 100% unmute' "$calls" || fail "install sets Master to full scale" "$(cat "$calls")"
pass "install unmutes Master at full scale"

never_sets() { ! grep -q '^amixer .*set Master' "$calls" || fail "$1" "$(cat "$calls")"; }

run "$migration" || fail "migration succeeds at the old install level"
never_sets "migration never changes Master at the old install level"
grep -q '^notify Speaker volume is capped at 80%.*run: amixer -c Generic_1 set Master 100% unmute$' "$calls" || fail "migration notifies once with the command" "$(cat "$calls")"
[[ $(grep -c '^notify' "$calls") == 1 ]] || fail "migration sends exactly one notification" "$(cat "$calls")"
grep -q 'run: amixer -c Generic_1 set Master 100% unmute' "$test_dir/out" || fail "migration prints the command" "$(cat "$test_dir/out")"
pass "migration leaves the old 80% alone and tells the user the command"

for level in '60 [69%] [-20.25dB] [on]' '87 [100%] [0.00dB] [on]'; do
  run "$migration" MASTER="$level" || fail "migration succeeds at $level"
  never_sets "migration never changes Master at $level"
  ! grep -q '^notify' "$calls" || fail "migration is silent at $level" "$(cat "$calls")"
done
pass "migration is silent at a user-chosen level or full scale"

run "$migration" HAS_ALC285=0 || fail "migration succeeds without an ALC285"
! grep -q -e '^amixer' -e '^notify' "$calls" || fail "migration skips machines without an ALC285" "$(cat "$calls")"
run "$migration" IS_ROG=0 || fail "migration succeeds off ROG hardware"
! grep -q -e '^amixer' -e '^notify' "$calls" || fail "migration skips non-ROG machines" "$(cat "$calls")"
pass "migration only acts on ROG machines with an ALC285"

rm "$soft_mixer"
run "$migration" || fail "migration succeeds without the soft mixer"
! grep -q -e '^amixer .*set Master' -e '^notify' "$calls" || fail "migration is silent when PipeWire drives Master" "$(cat "$calls")"
pass "migration only acts while the soft mixer is in use"
