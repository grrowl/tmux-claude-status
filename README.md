# tmux-claude-status

See what every Claude Code session in your tmux is doing, at a glance. A hook script tells tmux when Claude is working, when it needs you, and when it is done, and tmux shows that as colour in three places:

1. **Pane badge.** Each pane running Claude gets a coloured label in its border, e.g. a yellow "⚙ working" chip. Panes without Claude show nothing extra.
2. **Pane tint.** When Claude is waiting for your input, the whole pane background gets a subtle red tint, so you cannot miss it across a wall of splits.
3. **Window tab.** The tab in the status line takes the combined state of all panes in that window. It turns red if any Claude needs you, yellow if any is still working, and green once all are done.

The states are:

| Colour | State | Set by |
| --- | --- | --- |
| Yellow | working | you submit a prompt, or a tool call finishes |
| Red | needs you | a permission prompt appears, or Claude goes idle waiting for input |
| Green | done | Claude finishes its turn |
| (theme default) | cleared | the Claude session ends |

Subagents are handled correctly. The tab stays yellow while subagents run, because only the end of the whole turn sets green.

## Requirements

- tmux 3.2 or newer
- Claude Code with `~/.claude/` present
- python3 (used only by the installer to edit JSON safely)

## Install

```sh
git clone https://github.com/grrowl/tmux-claude-status
cd tmux-claude-status
./install.sh
```

The installer does three things:

1. It copies `tmux-status.sh` to `~/.claude/tmux-status.sh`.
2. It adds hooks to `~/.claude/settings.json` for the `UserPromptSubmit`, `PostToolUse`, `Notification`, `Stop`, and `SessionEnd` events. It backs the file up first, writes atomically, and refuses to touch a file that is not valid JSON. Claude Code reloads settings on its own, so running sessions pick the hooks up without a restart.
3. It writes `~/.claude/tmux-claude-status.conf` and sources it from your tmux config with a marked block. Your existing `pane-border-format` is captured and kept, and the badge is added in front of it. If a tmux server is running, the config is applied live.

Re-running the installer is safe and acts as an upgrade. It replaces its own hooks instead of duplicating them, and it keeps the border format it captured the first time.

Try it without waiting for Claude:

```sh
~/.claude/tmux-status.sh attention   # badge, tint, and red tab appear
~/.claude/tmux-status.sh clear       # everything back to normal
```

## Uninstall

```sh
./uninstall.sh
```

This removes the hooks from `settings.json` (and the `hooks` key itself if nothing else is left in it), removes the marked block from your tmux config, deletes both installed files, clears the live tmux state in every pane and window, and re-sources your own tmux config. Your tmux config is edited in place, so a symlinked `~/.tmux.conf` stays a symlink.

## How it works

Claude Code hooks run shell commands and inherit `$TMUX_PANE`, so the script always knows which pane its session lives in. On each event it stamps a `@claude_status` user option on that pane. The border badge renders from that option declaratively. The window tab colour is computed by the script, which reads `@claude_status` from every pane in the window and applies the priority attention > working > done.

The hook script never prints and always exits 0. That is deliberate, because Claude Code injects `UserPromptSubmit` hook output into the model's context, and a non-zero exit from a `Stop` hook blocks Claude from stopping.

## Customising

Colours and badge text live in two places:

- `~/.claude/tmux-claude-status.conf` has the border badge (`@claude_status_badge`). Note that styles inside it use the `#[fg=x]#[bg=y]` form, because a comma inside `#[fg=x,bg=y]` would break the surrounding tmux conditional.
- `~/.claude/tmux-status.sh` has the pane tint and the tab colours.

Edits to the conf apply on the next `tmux source-file ~/.claude/tmux-claude-status.conf`. Edits to the script apply on the next hook event. Both files are overwritten if you re-run the installer, except for the captured border format, which is kept.

## Caveats

- `pane-border-status top` adds a border line to every window, including windows with a single pane. Many people like this, since each pane gets a title bar. If you do not, this tool is not for you in its current form.
- The uninstaller resets `window-status-style` on every window. If you set that option on specific windows yourself, you will need to set it again.
- Claude sessions running outside tmux are unaffected. The script exits immediately when `$TMUX` is not set.

## License

MIT
