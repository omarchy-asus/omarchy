#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1792824363.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"

cat >"$test_dir/bin/omarchy-plugin-add" <<'STUB'
#!/bin/bash

echo "$*" >>"$PLUGIN_ADDS"
[[ -z ${PLUGIN_ADD_FAILS:-} ]] || exit 1
mkdir -p "$HOME/.config/omarchy/plugins/io.github.omarchy-asus.panel/.git"
STUB

chmod +x "$test_dir/bin/"*

export PLUGIN_ADDS="$test_dir/plugin-adds"

home="$test_dir/home"
plugins="$home/.config/omarchy/plugins"

reset_home() {
  rm -rf "$home"
  mkdir -p "$plugins"
  : >"$PLUGIN_ADDS"
}

run_migration() {
  HOME="$home" PATH="$test_dir/bin:$PATH" bash -euo pipefail "$migration" >"$test_dir/out"
}

reset_home
ln -s /usr/share/omarchy/plugins/omarchy-asus.g16 "$plugins/omarchy-asus.g16"
run_migration
[[ ! -e $plugins/omarchy-asus.g16 && ! -L $plugins/omarchy-asus.g16 ]] ||
  fail "migration removes the packaged widget's link"
pass "migration removes the packaged widget's link"
[[ $(<"$PLUGIN_ADDS") == "https://github.com/omarchy-asus/omarchy-asus-plugin --enable --yes" ]] ||
  fail "migration adds and enables the omarchy-asus plugin" "$(cat "$PLUGIN_ADDS")"
pass "migration adds and enables the omarchy-asus plugin"

reset_home
ln -s /usr/share/omarchy/plugins/omarchy-asus.g16 "$plugins/omarchy-asus.g16"
mkdir -p "$plugins/io.github.omarchy-asus.panel/.git"
run_migration
[[ ! -L $plugins/omarchy-asus.g16 && ! -s $PLUGIN_ADDS ]] ||
  fail "migration only removes the link when the plugin is already there" "$(cat "$PLUGIN_ADDS")"
pass "migration only removes the link when the plugin is already there"

reset_home
ln -s /usr/share/omarchy/plugins/omarchy-asus.g16 "$plugins/omarchy-asus.g16"
PLUGIN_ADD_FAILS=1 run_migration ||
  fail "migration does not fail the update when the plugin cannot be added"
grep -q "omarchy-plugin-add https://github.com/omarchy-asus/omarchy-asus-plugin --enable" "$test_dir/out" ||
  fail "migration says how to add the plugin later" "$(cat "$test_dir/out")"
pass "migration says how to add the plugin later when the add fails"

reset_home
run_migration
[[ ! -s $PLUGIN_ADDS ]] || fail "migration leaves a machine without the link alone"
pass "migration leaves a machine without the link alone"

reset_home
mkdir -p "$test_dir/mine"
ln -s "$test_dir/mine" "$plugins/omarchy-asus.g16"
run_migration
[[ -L $plugins/omarchy-asus.g16 && ! -s $PLUGIN_ADDS ]] ||
  fail "migration leaves a link of the user's own under that id alone"
pass "migration leaves a link of the user's own under that id alone"
