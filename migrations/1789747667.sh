echo "Install rtkit so PipeWire gets realtime priority"

# PipeWire requests realtime scheduling via RealtimeKit at startup, but rtkit
# is not a dependency of Arch's pipewire packages and the rlimits fallback is
# not configured either (see https://github.com/omacom/omarchy/issues/9390).
# Without it, audio threads run at SCHED_OTHER nice 0 and produce xruns under
# sustained load.
installed_here=0
pacman -Q rtkit &>/dev/null || installed_here=1
omarchy-pkg-add rtkit

# Restart only a session that started without rtkit: one where this run
# installed it, or where the portal or PipeWire is still running from before
# rtkit was installed (another user's run installed it during this session).
# A machine that had rtkit before the session (installed by hand, or by the
# installer) already has realtime audio, and its portal and PipeWire are left
# alone.
rtkit_newer_than_session() {
  local installed unit started
  installed=$(LC_ALL=C pacman -Qi rtkit 2>/dev/null | sed -n 's/^Install Date *: *//p')
  [[ -n $installed ]] && installed=$(date -d "$installed" +%s 2>/dev/null) || return 1
  for unit in xdg-desktop-portal.service pipewire.service; do
    started=$(systemctl --user show "$unit" -p ExecMainStartTimestamp --value 2>/dev/null) || continue
    [[ -n $started && $started != n/a ]] || continue
    started=$(date -d "$started" +%s 2>/dev/null) || continue
    (( installed >= started )) && return 0
  done
  return 1
}

if ! (( installed_here )) && ! rtkit_newer_than_session; then
  exit 0
fi

# The portal reads rtkit's realtime budget once, so restart it first: PipeWire
# clients that reconnect to a stale portal take a hard RLIMIT_RTTIME of 0.
systemctl --user try-restart xdg-desktop-portal.service 2>/dev/null || true

# rtkit only takes effect when PipeWire re-requests priority at startup.
# Restart the audio units if they are running; harmless when idle or as root.
systemctl --user try-restart pipewire.service pipewire-pulse.service wireplumber.service 2>/dev/null || true
