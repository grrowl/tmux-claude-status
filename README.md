# tmux-claude-status

Visual feedback for Claude Code across tmux sessions, windows, and panes.

![working](docs/img/working.png)
![blocked](docs/img/blocked.png)
![idle](docs/img/idle.png)

This repo installs hooks into claude which report current status to the containing tmux session, window, and pane. When not running in tmux, it does nothing.

You get feedback in three places:

1. A badge in the pane border. "⇄ working", "✻ blocked", "· idle".
2. A red tint over the whole pane when Claude is blocked on you.
3. The window tab shows the aggregate of all claude panes in it -- red if any are blocked, yellow if any are working. Idle leaves the tab alone; your theme keeps it.

This is kept intentionally simple. I tried so many agent monitoring wrappers like cmux, herdr, etc. and they're all in some way super annoying to use. I already use tmux. Claude Code already uses tmux. Tmux has great support in terminal emulators, you can remote into it, you can detach and attach it — idc if it smells like the 80s, it works.

This shouldn't mess with your existing tmux config/setup, apart from adding a bar to the top of your pane if you don't already have one.

## Install

```sh
git clone https://github.com/grrowl/tmux-claude-status
cd tmux-claude-status
./install.sh
```

Because I'm wary of all these tools who take over your system and break shit, I'll tell you exactly what this script does:

* Adds two files to `~/.claude`: `tmux-status.sh` (the hook script) and `tmux-claude-status.conf` (badge text and colours).
* Adds one `source` line to your `~/.tmux.conf`, or to `~/.config/tmux/tmux.conf` if that's the one you use. It goes inside `# >>> tmux-claude-status >>>` markers so the uninstaller can find it again.
* Adds the six hooks below to `~/.claude/settings.json`. It backs that file up first, and it won't touch the file if the JSON is invalid.

That's it. Running Claude sessions pick it up without a restart.

You can preview inside an existing tmux session:

```sh
~/.claude/tmux-status.sh blocked
~/.claude/tmux-status.sh idle
~/.claude/tmux-status.sh clear
```

## Uninstall

```sh
./uninstall.sh
```

Safely removes everything install added. The only thing kept is a backup of your `settings.json` at `~/.claude/settings.json.tmux-claude-status.bak`, in case you want to check nothing else changed.

## How it works

![two panes, one working and one blocked, with the window tabs coloured to match](docs/img/how-it-works.png)

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

Some details we paid attention to:

- Subagents don't fool it. The tab stays yellow until the whole turn is done.
- No timers. Red fires the instant Claude asks a question or needs permission.
- The focused window's tab color overrides to yellow and red when attention is needed (my current tab is usually blue).
- Your existing `pane-border-format` is kept. The badge is added in front of it.
- The installer edits `settings.json` atomically, backs it up first, refuses to touch invalid JSON, and won't duplicate hooks if you run it twice. A symlinked `.tmux.conf` stays a symlink.
- Claude outside tmux is a safe no-op.

One known edge case: if you kill a pane while it's blocked or working, the window tab keeps its colour until another Claude event fires in that window. Nothing re-aggregates on pane death.

## Customise

Badge text and border colours live in `~/.claude/tmux-claude-status.conf`. Tint and tab colours live in `~/.claude/tmux-status.sh`. Edit away, but re-running the installer overwrites both.

## Requirements

tmux 3.2+, Claude Code, python3 (installer only).

Heads up: this turns on `pane-border-status top`, so every pane gets a title bar. If you hate that, you'll hate this (works for me).

## License

MIT
