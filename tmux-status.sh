#!/usr/bin/env bash
# tmux-claude-status — Claude Code hook that colours tmux by Claude's status.
# Usage (called by Claude Code hooks): tmux-status.sh <working|attention|done|clear>
#
# Layer 1: sets @claude_status on this pane; the pane border badge renders from it.
# Layer 2: tints this pane's background while Claude needs attention.
# Layer 3: colours the window tab from the aggregate of all panes in the window.

# Claude Code injects UserPromptSubmit hook stdout into the model's context,
# and a non-zero exit from a Stop hook blocks Claude from stopping — so this
# script must never print and must always exit 0.
exec >/dev/null 2>&1

[ -n "$TMUX" ] && [ -n "$TMUX_PANE" ] || exit 0
command -v tmux >/dev/null || exit 0

state="$1"

case "$state" in
  attention)
    # Notifications also fire when a *finished* session sits idle. Only escalate
    # to attention when Claude is mid-turn (working): that means it is genuinely
    # blocked on you — a permission prompt or a question. A done/idle session
    # stays done instead of nagging red.
    cur=$(tmux show -pv -t "$TMUX_PANE" @claude_status 2>/dev/null)
    { [ "$cur" = working ] || [ "$cur" = attention ]; } || exit 0
    tmux set -p -t "$TMUX_PANE" @claude_status attention
    ;;
  working|done) tmux set -p -t "$TMUX_PANE" @claude_status "$state" ;;
  clear)        tmux set -p -u -t "$TMUX_PANE" @claude_status ;;
  *) exit 0 ;;
esac

# Layer 2: background tint only while attention is needed; anything louder is noisy.
if [ "$state" = attention ]; then
  tmux set -p -t "$TMUX_PANE" window-style 'bg=#2a1515'
else
  tmux set -p -u -t "$TMUX_PANE" window-style
fi

# Layer 3: window tab aggregates every pane's status, attention > working > done.
# window-status-current-style (themes often set it globally) would hide the
# colour on the focused window's tab, so working/attention override it
# per-window too. "done" defers to the theme there: green on the tab you are
# already looking at is noise, and the pane badge shows it anyway.
statuses=$(tmux list-panes -t "$TMUX_PANE" -F '#{@claude_status}')
case "$statuses" in
  *attention*)
    tmux set -w -t "$TMUX_PANE" window-status-style 'fg=white,bg=red'
    tmux set -w -t "$TMUX_PANE" window-status-current-style 'fg=white,bg=red,bold'
    ;;
  *working*)
    tmux set -w -t "$TMUX_PANE" window-status-style 'fg=black,bg=yellow'
    tmux set -w -t "$TMUX_PANE" window-status-current-style 'fg=black,bg=yellow,bold'
    ;;
  *done*)
    tmux set -w -t "$TMUX_PANE" window-status-style 'fg=black,bg=green'
    tmux set -w -u -t "$TMUX_PANE" window-status-current-style
    ;;
  *)
    tmux set -w -u -t "$TMUX_PANE" window-status-style
    tmux set -w -u -t "$TMUX_PANE" window-status-current-style
    ;;
esac

exit 0
