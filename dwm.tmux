#!/bin/sh
# TPM entrypoint. All runtime paths are relative to this checkout.
set -eu

plugin_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)

shell_quote() {
    escaped=$(printf '%s' "$1" | sed "s/'/'\\\\''/g")
    printf "'%s'" "$escaped"
}

tmux set-option -g @dwm-command "$(shell_quote "$plugin_dir/bin/dwm.tmux")"

# Preserve explicit native settings and do not reset them when reloading.
if [ -z "$(tmux show-options -gqv @dwm-loaded)" ]; then
    if [ "$(tmux show-options -gwv main-pane-width)" = 80 ]; then
        tmux set-option -gw main-pane-width 50%
    fi
    tmux set-option -g @dwm-loaded on
fi

# Allocate aliases without occupying another plugin's array slots.
aliases=$(tmux show-options -s command-alias)
next_alias=$(printf '%s\n' "$aliases" | awk '
    { i = $1; gsub(/[^0-9]/, "", i); if (i + 0 > max) max = i }
    END { print max + 1 }')

alias_index() {
    printf '%s\n' "$aliases" | awk -v name="$1" '
        {
            value = $0
            sub(/^[^ ]+[[:space:]]+/, "", value)
            sub(/^"/, "", value)
            if (index(value, name "=") == 1) {
                i = $1; gsub(/[^0-9]/, "", i); print i; exit
            }
        }'
}

register_alias() {
    alias_name=$1
    alias_body=$2
    alias_slot=$(alias_index "$alias_name")
    # Upgrade the old plugin's aliases, but leave unrelated legacy names alone.
    if [ -n "$alias_slot" ] && [ "${3:-}" = legacy ]; then
        previous=$(tmux show-options -sv "command-alias[$alias_slot]")
        if [ "$previous" != "$alias_name=run-shell \"dwm.tmux $alias_name\"" ]; then
            return
        fi
    fi
    if [ -z "$alias_slot" ]; then
        alias_slot=$next_alias
        next_alias=$((next_alias + 1))
        aliases="$aliases
command-alias[$alias_slot] $alias_name=$alias_body"
    fi
    tmux set-option -s "command-alias[$alias_slot]" "$alias_name=$alias_body"
}

for action in newpane newpanecurdir killpane layouttile incmfact decmfact; do
    body="run-shell \"#{@dwm-command} $action #{pane_id}\""
    register_alias "dwm-$action" "$body"
    register_alias "$action" "$body" legacy
done

while IFS='|' read -r action body legacy; do
    register_alias "dwm-$action" "$body"
    register_alias "$action" "$body" legacy
    register_alias "$legacy" "$body" legacy
done <<'ALIASES'
nextpane|select-pane -t :.+|nextpane
prevpane|select-pane -t :.-|prevpane
rotateccw|rotate-window -U ; select-pane -t ":.{top-left}"|rotateccw
rotatecw|rotate-window -D ; select-pane -t ":.{top-left}"|rotatecw
promote|swap-pane -s :. -t ":.{top-left}" ; select-pane -t ":.{top-left}"|zoom
toggle-zoom|resize-pane -Z|float
ALIASES

tmux source-file "$plugin_dir/lib/dwm.tmux"

# pane-exited does not retain the exited pane's window in tmux 3.2/3.5.
# Layout notifications do, and a pane count lets us distinguish pane removal
# from ordinary resizing or manual layout changes without launching a shell.
tmux list-windows -a -F '#{window_id}' | while IFS= read -r window; do
    tmux set-option -wF -t "$window" @dwm-pane-count '#{window_panes}'
    tmux set-option -wF -t "$window" @dwm-zoomed '#{window_zoomed_flag}'
done

# Remove only the previous version's known handler when upgrading a live server.
tmux show-hooks -g pane-exited | while IFS=' ' read -r option body; do
    if [ "$body" = 'run-shell "dwm.tmux layouttile"' ]; then
        tmux set-hook -gu "$option"
    fi
done

# Append to the hook array and reuse our entry on reload.
hooks=$(tmux show-hooks -g window-layout-changed)
hook_slot=$(printf '%s\n' "$hooks" | awk '
    /@dwm-command.*hook-retile/ {
        i = $1; gsub(/[^0-9]/, "", i); print i; exit
    }')
if [ -z "$hook_slot" ]; then
    hook_slot=$(printf '%s\n' "$hooks" | awk '
        { i = $1; gsub(/[^0-9]/, "", i); if (i + 0 > max) max = i }
        END { print max + 1 }')
fi
# Expand the event ID before resolving -t; defer window formats until that
# explicit target is selected. -C executes tmux commands without a shell.
hook_command='if-shell -Ft "#{hook_window}" "##{?@dwm-pane-count,##{!=:##{window_panes},##{@dwm-pane-count}},1}" { run-shell "##{@dwm-command} hook-retile #{hook_window}" } { set-option -wF -t "#{hook_window}" @dwm-zoomed "##{window_zoomed_flag}" }'
tmux set-hook -g "window-layout-changed[$hook_slot]" "run-shell -C '$hook_command'"

preset=$(tmux show-options -gqv @dwm-bindings)
case "$preset" in
    meta|prefix|both|none) ;;
    *) printf '%s\n' 'dwm.tmux: @dwm-bindings must be meta, prefix, both, or none' >&2; exit 1 ;;
esac

# Save existing bindings so changing presets can restore them. Never remove a
# binding the user has changed since we installed it.
binding() {
    # tmux 3.2's single-key filter drops modifiers (for example M-n).
    tmux list-keys -T "$1" | awk -v table="$1" -v key="$2" '
        {
            for (i = 1; i < NF - 1; i++) {
                if ($i == "-T" && $(i + 1) == table && $(i + 2) == key) {
                    print; exit
                }
            }
        }'
}

bind_group() {
    table=$1
    key_prefix=$2
    enabled=$3
    while read -r key action; do
        key=$key_prefix$key
        option="@dwm-binding-$table-$key"
        original_option="@dwm-original-$table-$key"
        installed=$(tmux show-options -gqv "$option")
        current=$(binding "$table" "$key")
        if [ "$enabled" = off ]; then
            if [ -n "$installed" ]; then
                if [ "$current" = "$installed" ]; then
                    original=$(tmux show-options -gqv "$original_option")
                    if [ "$original" = unbound ]; then
                        tmux unbind-key -q -T "$table" "$key"
                    else
                        restore_file=$(mktemp "${TMPDIR:-/tmp}/dwm-bindings.XXXXXX")
                        printf '%s\n' "$original" > "$restore_file"
                        tmux source-file "$restore_file"
                        rm -f "$restore_file"
                    fi
                fi
                tmux set-option -gu "$option"
                tmux set-option -gu "$original_option"
            fi
        elif [ -z "$installed" ]; then
            tmux set-option -g "$original_option" "${current:-unbound}"
            tmux bind-key -T "$table" "$key" "dwm-$action"
            tmux set-option -g "$option" "$(binding "$table" "$key")"
        elif [ "$current" = "$installed" ]; then
            tmux bind-key -T "$table" "$key" "dwm-$action"
            tmux set-option -g "$option" "$(binding "$table" "$key")"
        fi
    done <<'BINDINGS'
n newpane
w newpanecurdir
c killpane
j nextpane
k prevpane
< rotateccw
> rotatecw
Enter promote
t layouttile
Space toggle-zoom
h decmfact
l incmfact
BINDINGS
}

meta=off
prefix=off
case "$preset" in
    meta) meta=on ;;
    prefix) prefix=on ;;
    both) meta=on; prefix=on ;;
esac
bind_group root M- "$meta"
bind_group prefix '' "$prefix"
