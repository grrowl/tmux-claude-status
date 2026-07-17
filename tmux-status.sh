#!/usr/bin/env bash
# tmux-claude-status — Claude Code hook that colours tmux by Claude's status.
# Usage (called by Claude Code hooks):
#   tmux-status.sh <working|busy|blocked|idle|subagent-stop|clear>
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

status() { tmux show -pqv -t "$TMUX_PANE" @claude_status 2>/dev/null; }

# Reads the hook payload from stdin and prints "<from_subagent> <live_subagents>".
#
# agent_id is present only when a hook fires inside a subagent, so it is what
# tells a subagent's tool call apart from the main thread's. background_tasks
# lists what is still running right now, and is authoritative — we recount from
# it rather than keeping a counter, which is what keeps parallel subagents from
# racing and lets a missed SubagentStop heal on the next turn.
#
# Only type "subagent" counts. Background shells appear here too, and a dev
# server left running would otherwise pin the pane yellow forever. A subagent
# also still lists itself as running in its own SubagentStop payload, hence the
# id filter.
parse() {
  python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("0 0"); raise SystemExit
me = d.get("agent_id")
bg = d.get("background_tasks") or []
n = sum(1 for t in bg
        if isinstance(t, dict) and t.get("type") == "subagent"
        and t.get("status") == "running" and t.get("id") != me)
print("%d %d" % (1 if me else 0, n))
' 2>/dev/null
}

# States are purely event-driven — no idle timers. "blocked" is only wired to
# the permission_prompt notification and the AskUserQuestion tool, so red always
# means Claude is waiting on you right now.
case "$state" in
  working|blocked)
    tmux set -p -t "$TMUX_PANE" @claude_status "$state"
    ;;
  idle)
    # Stop. Recount live subagents from the payload: the main thread has
    # finished, so anything left running is background work, and this is also
    # where any drift from a raced or missed SubagentStop gets corrected.
    set -- $(parse)
    tmux set -p -t "$TMUX_PANE" @claude_status idle
    tmux set -p -t "$TMUX_PANE" @claude_agents "${2:-0}"
    ;;
  busy)
    # PostToolUse. Its only job is dropping blocked back to working once you
    # approve a prompt. Reading working already means there is nothing to write,
    # and reading idle means the main thread has stopped, so the call belongs to
    # a subagent. Blocked is the one genuinely ambiguous case — an approval and a
    # background subagent's tool call look identical — and so the only one worth
    # spawning a parser for. Everything else exits before the fork.
    [ "$(status)" = blocked ] || exit 0
    set -- $(parse)
    # A subagent's tool call must never clear a prompt you have not answered.
    [ "${1:-0}" = 1 ] && exit 0
    tmux set -p -t "$TMUX_PANE" @claude_status working
    ;;
  subagent-stop)
    # Only to clear the badge promptly; the next Stop would recount anyway.
    set -- $(parse)
    tmux set -p -t "$TMUX_PANE" @claude_agents "${2:-0}"
    ;;
  clear)
    tmux set -p -u -t "$TMUX_PANE" @claude_status
    tmux set -p -u -t "$TMUX_PANE" @claude_agents
    ;;
  *) exit 0 ;;
esac

# Layer 2: background tint only while blocked; anything louder is noisy. Keyed
# off the stored status rather than "$state" so a subagent event landing while
# Claude is blocked on you cannot clear the tint.
if [ "$(status)" = blocked ]; then
  tmux set -p -t "$TMUX_PANE" window-style 'bg=#2a1515'
else
  tmux set -p -u -t "$TMUX_PANE" window-style
fi

# Layer 3: window tab aggregates every pane's status, blocked > working > subagent.
# window-status-current-style (themes often set it globally) would hide the
# colour on the focused window's tab, so the active states override it per-window
# too. "idle" leaves the tab entirely to the theme: a coloured tab on every
# finished session is noise, and the pane badge shows idle anyway.
statuses=$(tmux list-panes -t "$TMUX_PANE" -F '#{@claude_status} #{?#{@claude_agents},subagent,}')
case "$statuses" in
  *blocked*)
    tmux set -w -t "$TMUX_PANE" window-status-style 'fg=white,bg=red'
    tmux set -w -t "$TMUX_PANE" window-status-current-style 'fg=white,bg=red,bold'
    ;;
  *working*)
    tmux set -w -t "$TMUX_PANE" window-status-style 'fg=black,bg=yellow'
    tmux set -w -t "$TMUX_PANE" window-status-current-style 'fg=black,bg=yellow,bold'
    ;;
  *subagent*)
    tmux set -w -t "$TMUX_PANE" window-status-style 'fg=black,bg=colour136'
    tmux set -w -t "$TMUX_PANE" window-status-current-style 'fg=black,bg=colour136,bold'
    ;;
  *)
    tmux set -w -u -t "$TMUX_PANE" window-status-style
    tmux set -w -u -t "$TMUX_PANE" window-status-current-style
    ;;
esac

exit 0
