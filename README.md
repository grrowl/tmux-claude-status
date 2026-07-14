# tmux-claude-status

Your tmux tells you what Claude Code is doing.

**Yellow** = working. **Red** = blocked on you. **Green** = idle.

You see it in three places:

1. A badge in the pane border. "⚙ working", "● blocked", "✓ idle".
2. A red tint over the whole pane when Claude is blocked on you.
3. The window tab, rolled up across every pane in it. Red beats yellow beats green.

No wrapper. No daemon. No workspace manager. You already have a Claude workflow, and it already runs in tmux. This adds colour and gets out of the way.

## Install

```sh
git clone https://github.com/grrowl/tmux-claude-status
cd tmux-claude-status
./install.sh
```

That's it. Running Claude sessions pick it up without a restart.

Don't want to wait for Claude to see it?

```sh
~/.claude/tmux-status.sh blocked
~/.claude/tmux-status.sh clear
```

## Uninstall

```sh
./uninstall.sh
```

Removes everything it added. The hooks, the tmux config block, the files, the live colours. Nothing left behind.

## How it works

Claude Code hooks run a small shell script on six events:

| Event | Matcher | State |
|---|---|---|
| `UserPromptSubmit` | — | working |
| `PostToolUse` | — | working |
| `PreToolUse` | `AskUserQuestion` | blocked |
| `Notification` | `permission_prompt` | blocked |
| `Stop` | — | idle |
| `SessionEnd` | — | clear |

The script knows its own pane from `$TMUX_PANE` and stamps a `@claude_status` option on it. The border badge renders from that, and the tab takes the most urgent status of any pane in the window.

Some details it gets right:

- Subagents don't fool it. The tab stays yellow until the whole turn is done.
- No timers. Red fires the instant Claude asks a question or needs permission, and only then. A finished session sits green forever — there's no "you've been idle 60 seconds" nag.
- The focused window's tab goes yellow and red too, even if your theme styles the current tab. It skips green there, because green on the tab you're already looking at is noise.
- Your existing `pane-border-format` is kept. The badge is added in front of it.
- The installer edits `settings.json` atomically, backs it up first, refuses to touch invalid JSON, and won't duplicate hooks if you run it twice. A symlinked `.tmux.conf` stays a symlink.
- Claude outside tmux? The script exits instantly. Nothing happens.

## Customise

Badge text and border colours live in `~/.claude/tmux-claude-status.conf`. Tint and tab colours live in `~/.claude/tmux-status.sh`. Edit away. Re-running the installer overwrites both, but keeps the border format it captured from you the first time.

## Requirements

tmux 3.2+, Claude Code, python3 (installer only).

Heads up: this turns on `pane-border-status top`, so every pane gets a title bar. If you hate that, you'll hate this.

## License

MIT
