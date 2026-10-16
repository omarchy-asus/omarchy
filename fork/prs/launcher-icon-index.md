Branch: `perf/launcher-icon-index`

# Rescan the launcher icon index at most once a minute on open

Opening the menu walked every icon theme with find (about 9,000 paths, 75 ms) and indexed each path in its own JS callback on the GUI thread, while the menu was animating in. Desktop entry changes still rescan at once; an open now only rescans when the last scan is over a minute old, and a scan is indexed in a single pass over the collected output.

**How tested.** The focused shell tests for the touched code pass headless; `./test/all` shows no new failures against stock `quattro`.

This pull request was written with Claude Code.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
