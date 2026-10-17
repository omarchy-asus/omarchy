Branch: `perf/launcher-icon-index`

# Rescan the launcher icon index at most once a minute on open

Opening the menu walked every icon theme with find (about 9,000 paths, 75 ms) and indexed each path in its own JS callback on the GUI thread, while the menu was animating in. Desktop entry changes still rescan at once; an open now only rescans when the last scan is over a minute old, and a scan is indexed in a single pass over the collected output.

An app-list change whose debounce fires while a scan runs is not dropped: one more scan runs when that scan exits, and the open throttle does not hold it back, so a newly installed app gets its icon at once.

**Overlap.** #14992 (not ours) edits the same file and is complementary: it skips `valuesChanged` emissions that repeat the same apps, while this throttles the rescan on open and indexes a scan in one pass. The two merge without conflict (checked 2026-10-17).

**How tested.** The focused shell tests for the touched code pass headless; `./test/all` shows no new failures against stock `quattro`.

This pull request was written with Claude Code.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
