#!/usr/bin/env bash
# tmux-claude-status — Claude Code hook that colours tmux by Claude's status.
# Usage (called by Claude Code hooks): tmux-status.sh <working|blocked|idle|clear>
#
# Layer 1: sets @claude_status on this pane; the pane border badge renders from it.
# Layer 2: tints this pane's background while Claude is blocked on you.
# Layer 3: colours the window tab from the aggregate of all panes in the window.

# Claude Code injects UserPromptSubmit hook stdout into the model's context,
# and exit code 2 from a Stop hook blocks Claude from stopping — so this
# script must never print and must always exit 0.
exec >/dev/null 2>&1

[ -n "$TMUX" ] && [ -n "$TMUX_PANE" ] || exit 0
command -v tmux >/dev/null || exit 0

state="$1"

# States are purely event-driven — no idle timers. "blocked" is only wired to
# the permission_prompt notification and the AskUserQuestion tool, so red always
# means Claude is waiting on you right now.
case "$state" in
  working|blocked|idle) tmux set -p -t "$TMUX_PANE" @claude_status "$state" ;;
  clear)                tmux set -p -u -t "$TMUX_PANE" @claude_status ;;
  *) exit 0 ;;
esac

# Layer 2: background tint only while blocked; anything louder is noisy.
if [ "$state" = blocked ]; then
  tmux set -p -t "$TMUX_PANE" window-style 'bg=#2a1515'
else
  tmux set -p -u -t "$TMUX_PANE" window-style
fi

# Layer 3: window tab aggregates every pane's status, blocked > working.
# window-status-current-style (themes often set it globally) would hide the
# colour on the focused window's tab, so blocked/working override it per-window
# too. "idle" leaves the tab entirely to the theme: a coloured tab on every
# finished session is noise, and the pane badge shows idle anyway.
statuses=$(tmux list-panes -t "$TMUX_PANE" -F '#{@claude_status}')
case "$statuses" in
  *blocked*)
    tmux set -w -t "$TMUX_PANE" window-status-style 'fg=white,bg=red'
    tmux set -w -t "$TMUX_PANE" window-status-current-style 'fg=white,bg=red,bold'
    ;;
  *working*)
    tmux set -w -t "$TMUX_PANE" window-status-style 'fg=black,bg=yellow'
    tmux set -w -t "$TMUX_PANE" window-status-current-style 'fg=black,bg=yellow,bold'
    ;;
  *)
    tmux set -w -u -t "$TMUX_PANE" window-status-style
    tmux set -w -u -t "$TMUX_PANE" window-status-current-style
    ;;
esac

exit 0
