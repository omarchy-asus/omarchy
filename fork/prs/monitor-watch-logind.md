Branch: `perf/monitor-watch-logind`

# Reconcile clamshell state on logind events instead of a 2s poll

While a laptop was docked, the monitor watcher re-ran the whole clamshell sync (hyprctl, jq, flock and friends) every 2 seconds as a backstop for lid drift the Hyprland binds can miss, mostly across suspend. That cost about 6% of a core for as long as an external display was attached.

Listen to logind instead: its PrepareForSleep(false) resume signal and its LidClosed property change are exactly the moments that drift can happen. Each runs the same sync with the delayed retries a monitor change gets.

Only a laptop listens to logind, as before when the backstop only ran on a docked laptop; the monitor is started again if it exits (a logind restart). logind announces `LidClosed` with `PropertiesChanged`: its introspection marks only `Docked` and `OnExternalPower` as not emitting. A real lid close has not been watched yet.

**How tested.** The focused shell tests for the touched code pass headless; `./test/all` shows no new failures against stock `quattro`.

This pull request was written with Claude Code.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
