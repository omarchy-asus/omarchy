#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin"
export CALL_LOG="$tmp_dir/calls" INSTALLED="$tmp_dir/installed"
export PATH="$tmp_dir/bin:$ROOT/bin:$PATH"

migration=$(grep -l 'Install rtkit so PipeWire gets realtime priority' "$ROOT"/migrations/*.sh)

# pacman knows a package once its name is in $INSTALLED; -S adds it.
cat >"$tmp_dir/bin/pacman" <<'SH'
#!/bin/bash
printf 'pacman %s\n' "$*" >>"$CALL_LOG"
case $1 in
-Q) grep -qFx -- "${!#}" "$INSTALLED" 2>/dev/null ;;
-Qi) grep -qFx -- "${!#}" "$INSTALLED" 2>/dev/null && printf 'Name            : %s\nInstall Date    : %s\n' "${!#}" "$RTKIT_INSTALL_DATE" ;;
-S) printf '%s\n' "${!#}" >>"$INSTALLED" ;;
esac
SH
cat >"$tmp_dir/bin/sudo" <<'SH'
#!/bin/bash
"$@"
SH
# `show` answers when this user's portal or PipeWire started; empty when the
# unit is not running.
cat >"$tmp_dir/bin/systemctl" <<'SH'
#!/bin/bash
if [[ $2 == show ]]; then
  case $3 in
  xdg-desktop-portal.service) printf '%s\n' "${PORTAL_STARTED-$PIPEWIRE_STARTED}" ;;
  *) printf '%s\n' "$PIPEWIRE_STARTED" ;;
  esac
  exit 0
fi
printf 'systemctl %s\n' "$*" >>"$CALL_LOG"
SH
chmod +x "$tmp_dir/bin"/*

export PIPEWIRE_STARTED="Sun 2026-10-18 09:00:00 UTC" RTKIT_INSTALL_DATE="Sat 17 Oct 2026 08:00:00 AM UTC"

run_migration() {
  : >"$CALL_LOG"
  bash -euo pipefail "$migration" >/dev/null
}

# rtkit missing: it is installed, then the portal and the audio units restart.
: >"$INSTALLED"
run_migration
grep -qFx rtkit "$INSTALLED" || fail "a machine without rtkit gets it"
grep -qF 'systemctl --user try-restart xdg-desktop-portal.service' "$CALL_LOG" ||
  fail "installing rtkit restarts the portal" "$(cat "$CALL_LOG")"
grep -qF 'systemctl --user try-restart pipewire.service pipewire-pulse.service wireplumber.service' "$CALL_LOG" ||
  fail "installing rtkit restarts PipeWire" "$(cat "$CALL_LOG")"
portal_line=$(grep -n 'xdg-desktop-portal' "$CALL_LOG" | cut -d: -f1)
pipewire_line=$(grep -n 'pipewire.service' "$CALL_LOG" | cut -d: -f1)
(( portal_line < pipewire_line )) || fail "the portal restarts before PipeWire" "$(cat "$CALL_LOG")"
pass "a machine without rtkit gets it, and the portal and PipeWire restart"

# rtkit already there before this session started (installed by hand, or by
# the installer): PipeWire already has its realtime budget, so nothing is
# installed or restarted.
run_migration
if grep -q -e '^pacman -S' -e '^systemctl' "$CALL_LOG"; then
  fail "a machine that has rtkit is left alone" "$(cat "$CALL_LOG")"
fi
PIPEWIRE_STARTED="" PORTAL_STARTED="" run_migration
if grep -q -e '^pacman -S' -e '^systemctl' "$CALL_LOG"; then
  fail "a session without PipeWire running is left alone" "$(cat "$CALL_LOG")"
fi
pass "a machine that had rtkit before the session installs and restarts nothing"

# Another user's run installed rtkit after this user's PipeWire started: this
# session still runs without realtime priority, so it restarts.
RTKIT_INSTALL_DATE="Sun 18 Oct 2026 10:00:00 AM UTC" run_migration
grep -q '^pacman -S' "$CALL_LOG" && fail "rtkit is not installed twice"
grep -qF 'systemctl --user try-restart pipewire.service' "$CALL_LOG" ||
  fail "a session that started before rtkit restarts PipeWire" "$(cat "$CALL_LOG")"
pass "a session that started before another user installed rtkit restarts"

# PipeWire was restarted after that install but the portal was not: the
# portal still holds the old realtime budget, so both restart.
PORTAL_STARTED="Sun 2026-10-18 09:00:00 UTC" PIPEWIRE_STARTED="Sun 2026-10-18 11:00:00 UTC" \
  RTKIT_INSTALL_DATE="Sun 18 Oct 2026 10:00:00 AM UTC" run_migration
grep -qF 'systemctl --user try-restart xdg-desktop-portal.service' "$CALL_LOG" ||
  fail "a portal that started before rtkit is restarted" "$(cat "$CALL_LOG")"
pass "a portal that started before rtkit is restarted even when PipeWire did not"
