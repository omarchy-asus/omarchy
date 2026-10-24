#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1792824363.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"

# PLUGIN_ADD: ok clones and enables; clone-only clones, then fails to enable
# (no shell); anything else fails before cloning (no network).
cat >"$test_dir/bin/omarchy-plugin-add" <<'STUB'
#!/bin/bash

echo "add $*" >>"$CALLS"
case $PLUGIN_ADD in
  ok | clone-only)
    dir=$HOME/.config/omarchy/plugins/io.github.omarchy-asus.panel
    git init -q "$dir"
    git -C "$dir" remote add origin https://github.com/omarchy-asus/omarchy-asus-plugin
    [[ $PLUGIN_ADD == ok ]] || exit 1
    ;;
  *) exit 1 ;;
esac
STUB

# BAR_PUT=ok answers as a running shell does; otherwise as omarchy-bar does
# with no shell: a warning and status 0.
cat >"$test_dir/bin/omarchy-bar" <<'STUB'
#!/bin/bash

echo "bar $*" >>"$CALLS"
if [[ $BAR_PUT == ok ]]; then
  echo "$2 is on the bar"
else
  echo "omarchy-shell is not running; $2 was not put on the bar" >&2
fi
STUB

cat >"$test_dir/bin/omarchy-shell" <<'STUB'
#!/bin/bash
STUB

chmod +x "$test_dir/bin/"*

export CALLS="$test_dir/calls"

home="$test_dir/home"
plugins="$home/.config/omarchy/plugins"
link="$plugins/omarchy-asus.g16"
add_call="add https://github.com/omarchy-asus/omarchy-asus-plugin --enable --yes"

reset_home() {
  rm -rf "$home"
  mkdir -p "$plugins"
  : >"$CALLS"
}

old_link() {
  ln -s /usr/share/omarchy/plugins/omarchy-asus.g16 "$link"
}

# Runs the migration as omarchy-migrate does; its status is the migration's.
run_migration() {
  HOME="$home" PATH="$test_dir/bin:$PATH" PLUGIN_ADD="${PLUGIN_ADD:-ok}" BAR_PUT="${BAR_PUT:-ok}" \
    bash -euo pipefail "$migration" >"$test_dir/out" 2>&1
}

reset_home
old_link
run_migration || fail "migration completes when the plugin is added" "$(cat "$test_dir/out")"
[[ ! -e $link && ! -L $link ]] || fail "migration removes the packaged widget's link"
pass "migration removes the packaged widget's link"
[[ $(<"$CALLS") == "$add_call" ]] ||
  fail "migration adds and enables the omarchy-asus plugin" "$(cat "$CALLS")"
pass "migration adds and enables the omarchy-asus plugin"

reset_home
old_link
if PLUGIN_ADD=fail run_migration; then
  fail "migration stays pending when the plugin cannot be added"
fi
[[ -L $link ]] || fail "migration keeps the link while the plugin is missing"
grep -q "runs again with the next omarchy-update" "$test_dir/out" ||
  fail "migration says it will run again" "$(cat "$test_dir/out")"
pass "migration stays pending and keeps the link when the plugin cannot be added"
: >"$CALLS"
run_migration || fail "the next run completes the move" "$(cat "$test_dir/out")"
[[ ! -L $link && -d $plugins/io.github.omarchy-asus.panel/.git && $(<"$CALLS") == "$add_call" ]] ||
  fail "the next run completes the move" "$(cat "$CALLS")"
pass "the next run after a failed add completes the move"

reset_home
old_link
if PLUGIN_ADD=clone-only run_migration; then
  fail "migration stays pending when the plugin is cloned but not enabled"
fi
[[ -L $link ]] || fail "migration keeps the link until the plugin is enabled"
if BAR_PUT=none run_migration; then
  fail "migration stays pending while no shell puts the plugin on the bar"
fi
[[ -L $link ]] || fail "migration keeps the link while no shell answers"
pass "migration stays pending while the cloned plugin is not on the bar"
: >"$CALLS"
run_migration || fail "the next run puts the cloned plugin on the bar" "$(cat "$test_dir/out")"
[[ ! -L $link && $(<"$CALLS") == "bar put io.github.omarchy-asus.panel" ]] ||
  fail "the next run puts the cloned plugin on the bar without cloning it again" "$(cat "$CALLS")"
pass "the next run puts the cloned plugin on the bar without cloning it again"

reset_home
old_link
mkdir -p "$plugins/io.github.omarchy-asus.panel"
run_migration || fail "migration completes next to a plugin of the user's own under the id"
[[ ! -L $link && ! -s $CALLS ]] ||
  fail "migration only removes the link next to a plugin of the user's own under the id" "$(cat "$CALLS")"
pass "migration only removes the link next to a plugin of the user's own under the id"

reset_home
run_migration
[[ ! -s $CALLS ]] || fail "migration leaves a machine without the link alone"
pass "migration leaves a machine without the link alone"

reset_home
mkdir -p "$test_dir/mine"
ln -s "$test_dir/mine" "$link"
run_migration
[[ -L $link && ! -s $CALLS ]] || fail "migration leaves a link of the user's own under that id alone"
pass "migration leaves a link of the user's own under that id alone"
