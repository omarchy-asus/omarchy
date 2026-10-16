Branch: `asus/powerprofiles-external-owner`

# Let another power manager own the profile on plug and unplug

The battery service re-applies the remembered AC or battery profile on every power-source change. On machines where a vendor daemon or the user's own tool manages the profile, the two fight over each transition and the wrong profile is briefly applied. A powerprofiles-autoswitch-off toggle now makes those source-driven restores (and the login autodetect) a no-op, while a profile chosen explicitly still applies and is remembered.

**How tested.** `test/shell.d/powerprofiles-set-test.sh`: with the toggle set, a source change (no profile named) leaves the profile alone, and an explicit profile still applies and is remembered.

This pull request was written with Claude Code.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

**With `asus/ga605km-quiet-fans`.** The toggle also skips that branch's on/off call on source changes, so a quiet-fans state set on battery before the toggle was set stays until the owning tool writes a profile (which resets both platform-profile handlers).
