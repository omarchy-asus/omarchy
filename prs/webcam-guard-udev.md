Branch: `perf/webcam-guard-udev`

# Answer the webcam menu guard from udev instead of opening cameras

omarchy-hw-webcam ran v4l2-ctl over every video node, opening and powering up each camera whenever the menu opened. udev already records each node's V4L capabilities; read that, and fall back to asking the devices only for a node udev has no record of.

**How tested.** The focused shell tests for the touched code pass headless; `./test/all` shows no new failures against stock `quattro`.

This pull request was written with Claude Code.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
