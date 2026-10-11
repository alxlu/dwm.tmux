#!/bin/sh
# Each run owns its socket, sessions and processes. Never uses the default server.
set -eu

project_dir=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/dwmt.XXXXXX)
test_dir=$(CDPATH='' cd "$test_dir" && pwd -P)
socket=$test_dir/socket
runner=$project_dir/bin/dwm.tmux
loader=$project_dir/dwm.tmux

tm() {
    tmux -S "$socket" "$@"
}

cleanup() {
    status=$?
    trap - EXIT HUP INT TERM
    if [ "$status" -ne 0 ]; then
        tm list-windows -a -F '#{window_id} #{window_name} #{window_layout}' >&2 2>/dev/null || :
        tm list-panes -a -F '#{window_id} #{pane_id} index=#{pane_index} active=#{pane_active} #{pane_width}x#{pane_height}' >&2 2>/dev/null || :
        tm list-windows -a -F '#{window_id} panes=#{window_panes} cached=#{@dwm-pane-count} zoomed=#{@dwm-zoomed}' >&2 2>/dev/null || :
        tm show-options -gqv @test-layout-context >&2 2>/dev/null || :
        tm show-hooks -g pane-exited >&2 2>/dev/null || :
        tm show-hooks -g window-layout-changed >&2 2>/dev/null || :
    fi
    tm kill-server >/dev/null 2>&1 || :
    rm -rf "$test_dir"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

fail() {
    printf 'not ok - %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    [ "$1" = "$2" ] || fail "$3 (expected '$1', got '$2')"
}

ok() {
    printf 'ok - %s\n' "$1"
}

run() {
    sh "$runner" "$@"
}

load() {
    sh "$loader"
}

shell_quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

load_via_tmux() {
    tm run-shell "sh $(shell_quote "$loader")"
}

new_window() {
    tm new-window -P -F '#{window_id}' -n "$1" -c "$test_dir/cwd a"
}

active_pane() {
    tm display-message -p -t "$1" '#{pane_id}'
}

first_pane() {
    tm list-panes -t "$1" -F '#{pane_id}' | sed -n '1p'
}

pane_count() {
    tm display-message -p -t "$1" '#{window_panes}'
}

binding() {
    # tmux 3.2's optional key filter drops modifier bits before comparison.
    tm list-keys -T "$1" | awk -v key="$2" '
        { for (i = 1; i <= NF; i++) if ($i == "-T" && $(i + 2) == key) { print; exit } }'
}

wait_format() {
    wait_target=$1
    wait_format=$2
    wait_expected=$3
    wait_attempt=0
    while [ "$wait_attempt" -lt 100 ]; do
        wait_actual=$(tm display-message -p -t "$wait_target" "$wait_format")
        [ "$wait_actual" != "$wait_expected" ] || return 0
        sleep 0.05
        wait_attempt=$((wait_attempt + 1))
    done
    fail "timed out waiting for $wait_format='$wait_expected' (got '$wait_actual')"
}

assert_error() {
    if "$@" >"$test_dir/error" 2>&1; then
        fail "command unexpectedly succeeded: $*"
    fi
    [ -s "$test_dir/error" ] || fail "command failed without an explanation: $*"
}

command -v tmux >/dev/null 2>&1 || fail 'tmux is required'
mkdir "$test_dir/cwd a" "$test_dir/cwd b"
unset TMUX TMUX_PANE
SHELL=/bin/sh tmux -S "$socket" -f /dev/null new-session -d -s test -x 160 -y 48 'exec sleep 3600'
tm set-option -g default-shell /bin/sh
tm set-option -g default-command 'exec sleep 3600'
tm set-option -g status off
TMUX="$socket,$(tm display-message -p '#{pid}'),0"
export TMUX

# Loading must preserve user options, unrelated hooks and default shortcuts.
tm set-option -gw main-pane-width '61%'
tm set-option -g @dwm-bindings none
tm set-option -s 'command-alias[100]' 'newpane=run-shell "dwm.tmux newpane"'
tm set-option -s 'command-alias[101]' 'float=display-message foreign-float'
tm set-hook -g 'pane-exited[999]' 'set-option -g @test-other-hook fired'
tm set-hook -g 'window-layout-changed[999]' 'set-option -g @test-other-layout-hook fired'
tm set-hook -g 'window-layout-changed[998]' 'set-option -gF @test-layout-context "hook_window=#{hook_window} window_id=#{window_id} panes=#{window_panes} cached=#{@dwm-pane-count}"'
prefix_c=$(binding prefix c)
root_keys=$(tm list-keys -T root)
load
load_via_tmux
assert_eq '61%' "$(tm show-options -gwv main-pane-width)" 'loader preserves configured width'
assert_eq "$prefix_c" "$(binding prefix c)" 'none preset preserves prefix shortcuts'
assert_eq "$root_keys" "$(tm list-keys -T root)" 'none preset preserves root shortcuts'
hook_count=$(tm show-hooks -g window-layout-changed | awk '/hook-retile/ { n++ } END { print n+0 }')
assert_eq 1 "$hook_count" 'reloading registers the retile hook once'
tm show-hooks -g pane-exited | grep 'pane-exited\[999\]' >/dev/null || fail 'loader replaced an unrelated hook'
tm show-hooks -g window-layout-changed | grep 'window-layout-changed\[999\]' >/dev/null || fail 'loader replaced an unrelated layout hook'
case $(tm show-options -sqv 'command-alias[100]') in *@dwm-command*) ;; *) fail 'old project alias was not migrated' ;; esac
assert_eq 'float=display-message foreign-float' "$(tm show-options -sqv 'command-alias[101]')" 'loader preserves foreign aliases and slots'
tm set-hook -g 'window-layout-changed[9999]' 'set-option -g @test-layout-complete yes'
ok 'configuration reload, hook coexistence and opt-in shortcuts'

# A command target determines its window even if another window is current.
creation=$(new_window creation)
original_master=$(first_pane "$creation")
run newpane "$original_master"
assert_eq 2 "$(pane_count "$creation")" 'newpane creates a pane'
assert_eq "$original_master" "$(first_pane "$creation")" 'newpane preserves the master'
stack=$(active_pane "$creation")
[ "$stack" != "$original_master" ] || fail 'newpane does not select the new stack pane'
assert_eq "$test_dir/cwd a" "$(tm display-message -p -t "$stack" '#{pane_current_path}')" 'newpane inherits cwd'
tm respawn-pane -k -t "$stack" -c "$test_dir/cwd b" 'exec sleep 3600'
run newpanecurdir "$stack"
new_master=$(active_pane "$creation")
assert_eq "$new_master" "$(first_pane "$creation")" 'newpanecurdir promotes its new pane'
assert_eq "$test_dir/cwd b" "$(tm display-message -p -t "$new_master" '#{pane_current_path}')" 'newpanecurdir inherits selected stack cwd'
ok 'creation, focus, master promotion and directories with spaces'

# Pane and window numbers are presentation settings, not identities.
base_one=$(new_window base-one)
tm set-option -w -t "$base_one" pane-base-index 1
base_master=$(first_pane "$base_one")
run newpanecurdir "$base_master"
assert_eq 2 "$(pane_count "$base_one")" 'creation works with pane-base-index one'
assert_eq 1 "$(tm display-message -p -t "$(first_pane "$base_one")" '#{pane_index}')" 'master uses configured pane index'
run promote "$base_master"
assert_eq "$base_master" "$(first_pane "$base_one")" 'promotion works with pane-base-index one'
tm set-option -w -t "$base_one" main-pane-width '64%'
run incmfact "$base_master"
assert_eq '67%' "$(tm show-options -wv -t "$base_one" main-pane-width)" 'first ratio adjustment works'
tm move-window -s "$base_one" -t test:20
run decmfact "$base_master"
assert_eq '64%' "$(tm show-options -wv -t "$base_one" main-pane-width)" 'ratio survives renumbering'
tm set-option -w -t "$base_one" @dwm-step 08
run incmfact "$base_master"
assert_eq '72%' "$(tm show-options -wv -t "$base_one" main-pane-width)" 'custom step uses decimal arithmetic'
tm set-option -w -t "$base_one" @dwm-step 3
tm set-option -w -t "$base_one" main-pane-width 60
run incmfact "$base_master"
converted_width=$((60 * 100 / $(tm display-message -p -t "$base_one" '#{window_width}') + 3))
assert_eq "$converted_width%" "$(tm show-options -wv -t "$base_one" main-pane-width)" 'numeric native width converts to a percentage'
tm set-option -w -t "$base_one" main-pane-width '95%'
run incmfact "$base_master"
assert_eq '95%' "$(tm show-options -wv -t "$base_one" main-pane-width)" 'ratio is capped at 95 percent'
tm set-option -w -t "$base_one" main-pane-width '5%'
run decmfact "$base_master"
assert_eq '5%' "$(tm show-options -wv -t "$base_one" main-pane-width)" 'ratio is capped at 5 percent'
ok 'pane-base-index, ratio bounds and stable window identity'

kill_window=$(new_window kill-master)
kill_master=$(first_pane "$kill_window")
run newpane "$kill_master"
promoted=$(active_pane "$kill_window")
run newpane "$promoted"
promoted=$(tm list-panes -t "$kill_window" -F '#{pane_id}' | sed -n '2p')
run killpane "$kill_master"
assert_eq 2 "$(pane_count "$kill_window")" 'killpane closes the master'
assert_eq "$promoted" "$(first_pane "$kill_window")" 'killing master promotes first stack pane'
guard=$(new_window last-pane)
guard_pane=$(first_pane "$guard")
run killpane "$guard_pane"
assert_eq 1 "$(pane_count "$guard")" 'last pane is protected by default'
tm set-option -w -t "$guard" @dwm-kill-last on
run killpane "$guard_pane"
assert_eq '' "$(tm display-message -p -t "$guard" '#{window_id}' 2>/dev/null || :)" 'enabling last-pane deletion closes its window'
ok 'master deletion and last-pane guard'

# The pane exit hook must target the background window and preserve zoom.
background=$(new_window background)
background_master=$(first_pane "$background")
run newpane "$background_master"
run newpane "$background_master"
background_master_width=$(tm display-message -p -t "$background_master" '#{pane_width}')
tm select-layout -t "$background" even-horizontal >/dev/null
foreground=$(new_window foreground)
foreground_master=$(first_pane "$foreground")
run newpane "$foreground_master"
run newpane "$foreground_master"
tm select-layout -t "$foreground" even-horizontal >/dev/null
foreground_layout=$(tm display-message -p -t "$foreground" '#{window_layout}')
exiting=$(tm display-message -p -t "$background" '#{pane_pid}')
tm set-option -gu @test-other-hook
tm set-option -gu @test-other-layout-hook
tm set-option -gu @test-layout-complete
kill -TERM "$exiting"
wait_format "$background" '#{window_panes}' 2
wait_format "$foreground" '#{@test-other-hook}' fired
wait_format "$foreground" '#{@test-other-layout-hook}' fired
wait_format "$foreground" '#{@test-layout-complete}' yes
wait_format "$background_master" '#{pane_width}' "$background_master_width"
assert_eq "$foreground_layout" "$(tm display-message -p -t "$foreground" '#{window_layout}')" 'background exit preserves foreground layout'
ok 'background hook target and coexistence on actual pane exit'

run layouttile "$foreground_master"
tm select-pane -t "$foreground_master"
tm set-option -gu @test-layout-complete
tm dwm-toggle-zoom
wait_format "$foreground" '#{@test-layout-complete}' yes
assert_eq 1 "$(tm display-message -p -t "$foreground" '#{window_zoomed_flag}')" 'toggle-zoom enters fullscreen'
exiting=$(tm list-panes -t "$foreground" -F '#{pane_pid}' | sed -n '3p')
tm set-option -gu @test-other-hook
tm set-option -gu @test-layout-complete
kill -TERM "$exiting"
wait_format "$foreground" '#{window_panes}' 2
wait_format "$foreground" '#{@test-other-hook}' fired
wait_format "$foreground" '#{@test-layout-complete}' yes
assert_eq 1 "$(tm display-message -p -t "$foreground" '#{window_zoomed_flag}')" 'pane exit preserves fullscreen'
assert_eq "$foreground_master" "$(active_pane "$foreground")" 'pane exit preserves fullscreen selection'
ok 'fullscreen survives pane exit'

# Automation can be disabled without disabling explicit layout commands.
tm set-option -w -t "$foreground" @dwm-enabled off
run toggle-zoom "$foreground_master"
tm select-layout -t "$foreground" even-horizontal >/dev/null
disabled_layout=$(tm display-message -p -t "$foreground" '#{window_layout}')
run hook-retile "$foreground"
assert_eq "$disabled_layout" "$(tm display-message -p -t "$foreground" '#{window_layout}')" 'disabled window ignores automatic retile'
run layouttile "$foreground_master"
[ "$disabled_layout" != "$(tm display-message -p -t "$foreground" '#{window_layout}')" ] || fail 'explicit layout does not work in disabled window'
ok 'per-window automatic layout opt-out'

assert_error run not-a-command "$foreground_master"
assert_error run layouttile '%999999'
tm set-option -w -t "$foreground" @dwm-step invalid
assert_error run incmfact "$foreground_master"
tm set-option -w -t "$foreground" @dwm-step 3
run hook-retile '@999999'
ok 'invalid commands and targets report errors; stale hook targets are harmless'

tm set-option -g @dwm-bindings meta
load
case $(binding root M-n) in *newpane*) ;; *) fail 'meta preset lacks creation shortcut' ;; esac
assert_eq "$prefix_c" "$(binding prefix c)" 'meta preset preserves prefix shortcuts'
tm set-option -g @dwm-bindings both
load
case $(binding root M-n) in *newpane*) ;; *) fail 'both preset lacks Meta shortcut' ;; esac
case $(binding prefix c) in *killpane*) ;; *) fail 'both preset lacks prefix shortcut' ;; esac
tm set-option -g @dwm-bindings none
load
assert_eq "$prefix_c" "$(binding prefix c)" 'both to none restores prior prefix shortcut'
assert_eq "$root_keys" "$(tm list-keys -T root)" 'both to none restores prior Meta shortcuts'
tm set-option -g @dwm-bindings prefix
load
case $(binding prefix c) in *killpane*) ;; *) fail 'prefix preset lacks its shortcut' ;; esac
assert_eq "$root_keys" "$(tm list-keys -T root)" 'prefix preset restores Meta shortcuts'
tm set-option -g @dwm-bindings none
load
assert_eq "$prefix_c" "$(binding prefix c)" 'none preset restores prior prefix shortcut'
assert_eq "$root_keys" "$(tm list-keys -T root)" 'none preset restores prior Meta shortcuts'
tm set-option -g @dwm-bindings meta
load
tm bind-key -T root M-n display-message user-customized
custom_key=$(binding root M-n)
load
assert_eq "$custom_key" "$(binding root M-n)" 'reload preserves a user-modified binding'
tm set-option -g @dwm-bindings none
load
assert_eq "$custom_key" "$(binding root M-n)" 'disabling bindings preserves a user modification'
ok 'binding presets and restoration when switching'

# Install from source files only: no generated Go helper or architecture assets.
fresh=$test_dir/fresh
mkdir -p "$fresh/bin" "$fresh/lib"
cp "$project_dir/Makefile" "$fresh/Makefile"
cp "$project_dir/dwm.tmux" "$fresh/dwm.tmux"
cp "$project_dir/bin/dwm.tmux" "$fresh/bin/dwm.tmux"
cp "$project_dir/lib/dwm.tmux" "$fresh/lib/dwm.tmux"
stage=$test_dir/stage
prefix="/prefix with spaces and 'quote"
make -s -C "$fresh" install DESTDIR="$stage" PREFIX="$prefix"
installed=$stage$prefix/share/dwm.tmux
[ -x "$installed/dwm.tmux" ] || fail 'installed loader is not executable'
[ -x "$installed/bin/dwm.tmux" ] || fail 'installed runner is not executable'
[ -f "$installed/lib/dwm.tmux" ] || fail 'installed configuration is missing'
assert_eq "$prefix/share/dwm.tmux/bin/dwm.tmux" "$(readlink "$stage$prefix/bin/dwm.tmux")" 'staged symlink excludes DESTDIR'
loader=$installed/dwm.tmux
runner=$installed/bin/dwm.tmux
load_via_tmux
installed_window=$(new_window installed)
run newpane "$(first_pane "$installed_window")"
assert_eq 2 "$(pane_count "$installed_window")" 'staged runner works from path with spaces'
alias_pane=$(active_pane "$installed_window")
tm newpane
assert_eq 3 "$(pane_count "$installed_window")" 'installed loader resolves its runner without PATH setup'
run promote "$alias_pane"
make -s -C "$fresh" uninstall DESTDIR="$stage" PREFIX="$prefix"
[ ! -e "$installed/dwm.tmux" ] || fail 'uninstall leaves installed loader'
[ ! -L "$stage$prefix/bin/dwm.tmux" ] || fail 'uninstall leaves command symlink'
ok 'fresh source installation, DESTDIR, spaced paths, aliases and uninstall'

# A plugin-only install is self-contained and does not own an external CLI.
plugin_stage=$test_dir/plugin-stage
plugin_datadir='/one directory with spaces/dwm.tmux'
make -s -C "$fresh" install DESTDIR="$plugin_stage" PREFIX="$prefix" DATADIR="$plugin_datadir" INSTALL_CLI=no
plugin_installed=$plugin_stage$plugin_datadir
[ -x "$plugin_installed/dwm.tmux" ] || fail 'plugin-only loader is not executable'
[ -x "$plugin_installed/bin/dwm.tmux" ] || fail 'plugin-only runner is not executable'
[ -f "$plugin_installed/lib/dwm.tmux" ] || fail 'plugin-only configuration is missing'
[ ! -d "$plugin_stage$prefix/bin" ] || fail 'plugin-only install creates an external bin directory'
[ ! -L "$plugin_stage$prefix/bin/dwm.tmux" ] || fail 'plugin-only install creates an external command symlink'
loader=$plugin_installed/dwm.tmux
runner=$plugin_installed/bin/dwm.tmux
load_via_tmux
plugin_window=$(new_window plugin-only)
tm dwm-newpane
assert_eq 2 "$(pane_count "$plugin_window")" 'plugin-only namespaced alias finds its self-contained runner'
tm newpane
assert_eq 3 "$(pane_count "$plugin_window")" 'plugin-only legacy alias works without an external CLI'

# Reinstall/uninstall must leave an independently installed command untouched.
mkdir -p "$plugin_stage$prefix/bin"
sentinel_target=$test_dir/preexisting-cli
printf '%s\n' 'preexisting command' > "$sentinel_target"
ln -s "$sentinel_target" "$plugin_stage$prefix/bin/dwm.tmux"
make -s -C "$fresh" install DESTDIR="$plugin_stage" PREFIX="$prefix" DATADIR="$plugin_datadir" INSTALL_CLI=no
assert_eq "$sentinel_target" "$(readlink "$plugin_stage$prefix/bin/dwm.tmux")" 'plugin-only reinstall preserves an existing command symlink'
make -s -C "$fresh" uninstall DESTDIR="$plugin_stage" PREFIX="$prefix" DATADIR="$plugin_datadir" INSTALL_CLI=no
[ ! -e "$plugin_installed" ] || fail 'plugin-only uninstall leaves its plugin directory'
assert_eq "$sentinel_target" "$(readlink "$plugin_stage$prefix/bin/dwm.tmux")" 'plugin-only uninstall preserves an existing command symlink'
assert_eq 'preexisting command' "$(cat "$sentinel_target")" 'plugin-only uninstall preserves the external command contents'
ok 'one-directory plugin-only installation leaves an external CLI untouched'

printf 'All integration tests passed (%s).\n' "$(tmux -V)"
