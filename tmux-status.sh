#!/usr/bin/env bash
# tmux-claude-status — Claude Code hook that colours tmux by Claude's status.
# Usage (called by Claude Code hooks):
#   tmux-status.sh <working|busy|blocked|idle|stop-failed|subagent-stop|clear>
#
# "busy" means Claude did something, so it is not waiting on you. It only ever
# lowers blocked back to working; it never wakes an idle pane.
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

# Reads the hook payload from stdin and prints
# "<from_subagent> <live_subagents> <hook_event_name>".
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
    print("0 0 -"); raise SystemExit
me = d.get("agent_id")
bg = d.get("background_tasks") or []
n = sum(1 for t in bg
        if isinstance(t, dict) and t.get("type") == "subagent"
        and t.get("status") == "running" and t.get("id") != me)
print("%d %d %s" % (1 if me else 0, n, d.get("hook_event_name") or "-"))
' 2>/dev/null
}

# States are purely event-driven — no idle timers. "blocked" means the turn has
# stopped and needs you: a permission prompt, an AskUserQuestion, or a turn that
# died on an API error. Red always means come and look.
case "$state" in
  working)
    tmux set -p -t "$TMUX_PANE" @claude_status working
    ;;
  blocked)
    # Stamp when the pane *entered* blocked (transition only, so the +6s
    # "needs your permission" Notification re-assert does not refresh it).
    # The busy handler uses its age to tell a racing MessageDisplay flush
    # from a genuine one.
    [ "$(status)" = blocked ] ||
      tmux set -p -t "$TMUX_PANE" @claude_blocked_at "$(date +%s)"
    tmux set -p -t "$TMUX_PANE" @claude_status blocked
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
    # PostToolUse and MessageDisplay. Both mean the same thing: Claude is doing
    # something, so it is not waiting on you. Its only job is dropping blocked
    # back to working — when you approve a prompt (PostToolUse), or when you
    # dismiss a question with "Chat about this" and Claude answers in prose
    # instead, which fires no PostToolUse at all (MessageDisplay).
    #
    # Reading working already means there is nothing to write, and reading idle
    # means the main thread has stopped, so the call belongs to a subagent.
    # Blocked is the one genuinely ambiguous case — an approval and a background
    # subagent's tool call look identical — and so the only one worth spawning a
    # parser for. Everything else exits before the fork.
    #
    # MessageDisplay is NOT ordered before the question's PreToolUse. When the
    # pane is unfocused, Claude Code defers text display and flushes it as the
    # AskUserQuestion dialog renders, so the preamble's MessageDisplay races
    # PreToolUse and can land 1ms after blocked was set (observed live). Letting
    # it through cleared a prompt nobody had answered; the +6s Notification then
    # re-asserted blocked — the red → normal → red flicker. So a blocked state
    # younger than 5s is not MessageDisplay's to clear: the flush lands within
    # ~1s of the question rendering, while the dismissed-question path (read,
    # dismiss, Claude answers in prose) takes a human longer than 5s — and if it
    # somehow doesn't, Stop clears the pane at turn end anyway. PostToolUse is
    # exempt: it only fires while blocked when you approve a permission, and
    # that clear must stay instant.
    [ "$(status)" = blocked ] || exit 0
    set -- $(parse)
    # A subagent's tool call must never clear a prompt you have not answered.
    [ "${1:-0}" = 1 ] && exit 0
    if [ "${3:-}" = MessageDisplay ]; then
      blocked_at=$(tmux show -pqv -t "$TMUX_PANE" @claude_blocked_at 2>/dev/null)
      [ -n "$blocked_at" ] && [ $(( $(date +%s) - blocked_at )) -lt 5 ] && exit 0
    fi
    tmux set -p -t "$TMUX_PANE" @claude_status working
    ;;
  stop-failed)
    # StopFailure. The turn died on an API error, so it fires in Stop's place
    # and nothing else follows — the pane would sit yellow on work that gave up
    # minutes ago. Red is honest here: both mean come and look.
    #
    # A subagent that exhausts its retries fires this too, with its own
    # agent_id, and that must not paint the pane: the main thread gets the
    # error back and carries on to its own Stop. Rare enough that the fork
    # costs nothing.
    set -- $(parse)
    [ "${1:-0}" = 1 ] && exit 0
    # No background_tasks in this payload, so @claude_agents is left alone
    # rather than zeroed; the next Stop recounts it from the real list.
    tmux set -p -t "$TMUX_PANE" @claude_blocked_at "$(date +%s)"
    tmux set -p -t "$TMUX_PANE" @claude_status blocked
    ;;
  subagent-stop)
    # Only to clear the badge promptly; the next Stop would recount anyway.
    set -- $(parse)
    tmux set -p -t "$TMUX_PANE" @claude_agents "${2:-0}"
    ;;
  clear)
    tmux set -p -u -t "$TMUX_PANE" @claude_status
    tmux set -p -u -t "$TMUX_PANE" @claude_agents
    tmux set -p -u -t "$TMUX_PANE" @claude_blocked_at
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
