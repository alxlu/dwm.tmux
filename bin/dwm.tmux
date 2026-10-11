#!/bin/sh

# Keep state in tmux window options and pass stable IDs to every mutation.
usage() {
  printf '%s\n' 'Usage: dwm.tmux COMMAND [TARGET]' \
    'Commands: newpane newpanecurdir killpane nextpane prevpane' \
    '          rotateccw rotatecw zoom/promote float/toggle-zoom' \
    '          layouttile incmfact decmfact hook-retile' \
    'TARGET is a tmux pane ID (%N) or window ID (@N).' >&2
}

fail() {
  printf 'dwm.tmux: %s\n' "$1" >&2
  exit 1
}

case ${1-} in
  -h|--help|help) usage; exit 0 ;;
  newpane|newpanecurdir|killpane|nextpane|prevpane|rotateccw|rotatecw|zoom|promote|float|toggle-zoom|layouttile|incmfact|decmfact|hook-retile)
    command=$1 ;;
  '') usage; exit 1 ;;
  *) fail "unknown command: $1" ;;
esac
[ "$#" -le 2 ] || { usage; exit 1; }

target=${2-}
if [ -n "$target" ]; then
  case $target in
    @*|%*) id=${target#?} ;;
    *) fail 'TARGET must be a pane ID (%N) or window ID (@N)' ;;
  esac
  case $id in ''|*[!0-9]*) fail 'invalid TARGET ID' ;; esac
fi

# Fullscreen needs no lookup when its pane/window was supplied explicitly.
case $command in
  float|toggle-zoom)
    if [ -n "$target" ]; then
      exec tmux resize-pane -t "$target" -Z
    fi ;;
esac

format='#{window_id}|#{pane_id}|#{window_panes}|#{window_width}|#{window_zoomed_flag}|#{@dwm-enabled}|#{@dwm-kill-last}|#{@dwm-step}|#{main-pane-width}|#{@dwm-pane-count}|#{@dwm-zoomed}|#{pane_current_path}'
if [ "$command" = hook-retile ]; then
  [ -n "$target" ] || fail 'hook-retile requires a window or pane ID'
  # A window can disappear between its layout event and this process.
  context=$(tmux display-message -p -t "$target" "$format" 2>/dev/null) || exit 0
elif [ -n "$target" ]; then
  context=$(tmux display-message -p -t "$target" "$format") || exit 1
else
  context=$(tmux display-message -p "$format") || exit 1
fi
IFS='|' read -r window pane panes window_width zoomed enabled kill_last step main_width previous_panes previous_zoomed cwd <<CONTEXT
$context
CONTEXT
if [ -z "$window" ] || [ -z "$pane" ]; then
  [ "$command" = hook-retile ] && exit 0
  fail 'could not resolve the target window and pane'
fi

retile() {
  exec tmux select-layout -t "$window" main-vertical
}

case $command in
  nextpane)
    exec tmux select-pane -t "$pane" \; select-pane -t "$window.+" ;;
  prevpane)
    exec tmux select-pane -t "$pane" \; select-pane -t "$window.-" ;;
  rotateccw)
    exec tmux rotate-window -t "$window" -U \; select-pane -t "$window.{top-left}" ;;
  rotatecw)
    exec tmux rotate-window -t "$window" -D \; select-pane -t "$window.{top-left}" ;;
  float|toggle-zoom)
    exec tmux resize-pane -t "$pane" -Z ;;
  layouttile)
    retile ;;
  hook-retile)
    # Track count before tiling: our own layout/zoom events then become no-ops.
    tmux set-option -w -t "$window" @dwm-pane-count "$panes" \; \
      set-option -w -t "$window" @dwm-zoomed "$zoomed" || exit 1
    case $previous_panes in ''|*[!0-9]*) exit 0 ;; esac
    [ "$panes" -lt "$previous_panes" ] || exit 0
    case ${enabled:-on} in off|0|no|false) exit 0 ;; esac
    if [ "$zoomed" = 1 ]; then
      exec tmux set-option -w -t "$window" @dwm-zoomed 1 \; \
        resize-pane -t "$pane" -Z \; \
        select-layout -t "$window" main-vertical \; \
        resize-pane -t "$pane" -Z
    fi
    # tmux unzooms a window itself when a pane exits; retain its prior state.
    if [ "$previous_zoomed" = 1 ]; then
      exec tmux set-option -w -t "$window" @dwm-zoomed 1 \; \
        select-layout -t "$window" main-vertical \; \
        resize-pane -t "$pane" -Z
    fi
    retile ;;
  killpane)
    if [ "$panes" -eq 1 ]; then
      case ${kill_last:-off} in
        on|1|yes|true) exec tmux kill-pane -t "$pane" ;;
        off|0|no|false) exit 0 ;;
        *) fail '@dwm-kill-last must be on or off' ;;
      esac
    fi
    exec tmux kill-pane -t "$pane" \; select-layout -t "$window" main-vertical ;;
  incmfact|decmfact)
    step=${step:-3}
    case $step in ''|*[!0-9]*) fail '@dwm-step must be an integer from 1 to 90' ;; esac
    while [ "${step#0}" != "$step" ]; do step=${step#0}; done
    step=${step:-0}
    # Reject oversized integers before passing them to shell arithmetic.
    if [ "${#step}" -gt 2 ] || [ "$step" -lt 1 ] || [ "$step" -gt 90 ]; then
      fail '@dwm-step must be an integer from 1 to 90'
    fi
    case $main_width in
      *%) width=${main_width%\%} ;;
      *)
        case $main_width in ''|*[!0-9]*) fail 'main-pane-width must be a positive width or percentage' ;; esac
        while [ "${main_width#0}" != "$main_width" ]; do main_width=${main_width#0}; done
        main_width=${main_width:-0}
        [ "$window_width" -gt 0 ] || fail 'window width must be positive'
        width=$((main_width * 100 / window_width)) ;;
    esac
    case $width in ''|*[!0-9]*) fail 'main-pane-width must be a positive width or percentage' ;; esac
    while [ "${width#0}" != "$width" ]; do width=${width#0}; done
    width=${width:-0}
    if [ "$command" = incmfact ]; then
      width=$((width + step))
    else
      width=$((width - step))
    fi
    [ "$width" -ge 5 ] || width=5
    [ "$width" -le 95 ] || width=95
    exec tmux set-option -w -t "$window" main-pane-width "$width%" \; \
      select-layout -t "$window" main-vertical ;;
esac

# main-vertical assigns its master to the first pane in tmux's pane order.
# Read that pane's ID, supporting any pane-base-index and previous swaps.
pane_ids=$(tmux list-panes -t "$window" -F '#{pane_id}') || exit 1
IFS= read -r master <<PANES
$pane_ids
PANES
[ -n "$master" ] || fail 'could not resolve the master pane'

case $command in
  newpane)
    exec tmux split-window -t "$master" -c "$cwd" \; \
      select-layout -t "$window" main-vertical ;;
  newpanecurdir)
    new_pane=$(tmux split-window -t "$master" -c "$cwd" -P -F '#{pane_id}') || exit 1
    exec tmux swap-pane -s "$new_pane" -t "$master" \; \
      select-layout -t "$window" main-vertical \; \
      select-pane -t "$new_pane" ;;
  zoom|promote)
    [ "$pane" != "$master" ] || exec tmux select-pane -t "$pane"
    exec tmux swap-pane -s "$pane" -t "$master" \; select-pane -t "$pane" ;;
esac
