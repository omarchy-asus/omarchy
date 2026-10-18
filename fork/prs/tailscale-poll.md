Branch: `perf/tailscale-poll`

# Poll only Tailscale status while its panel is closed

Every 30 seconds each bar ran three tailscale clients: status, the exit-node list and the account list. Only status feeds the bar icon; exit nodes and accounts are shown in the panel alone. Fetch those when the panel opens and while it is open, so the background poll is one client.

**How tested.** The focused shell tests for the touched code pass headless; `./test/all` shows no new failures against stock `quattro`.

This pull request was written with Claude Code.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
