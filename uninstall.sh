#!/usr/bin/env bash
# tmux-claude-status uninstaller.
# Removes the Claude Code hooks, the tmux config block, the installed files,
# and clears any live tmux state — no trace left behind.
set -uo pipefail

CLAUDE_DIR="$HOME/.claude"
SCRIPT_DEST="$CLAUDE_DIR/tmux-status.sh"
CONF_DEST="$CLAUDE_DIR/tmux-claude-status.conf"
SETTINGS="$CLAUDE_DIR/settings.json"

command -v python3 >/dev/null || { echo "error: python3 is required" >&2; exit 1; }

# 1. Remove our hooks from Claude Code global settings (atomic, backup).
if [ -f "$SETTINGS" ]; then
  python3 - "$SETTINGS" <<'PY' || echo "warning: failed to update settings; remove tmux-status.sh hooks manually" >&2
import json, os, shutil, sys

path = sys.argv[1]
with open(path) as f:
    raw = f.read()
try:
    settings = json.loads(raw) if raw.strip() else {}
except ValueError as e:
    sys.exit(f"error: {path} is not valid JSON ({e}); not touching it")
shutil.copy2(path, path + ".tmux-claude-status.bak")

MARK = "tmux-status.sh"
changed = False
hooks = settings.get("hooks")
if isinstance(hooks, dict):
    for event in list(hooks):
        groups = hooks[event]
        kept_groups = []
        for group in groups:
            entries = group.get("hooks")
            if isinstance(entries, list):
                kept = [h for h in entries if MARK not in str(h.get("command", ""))]
                if kept != entries:
                    changed = True
                if not kept:
                    continue
                group = {**group, "hooks": kept}
            kept_groups.append(group)
        if kept_groups:
            hooks[event] = kept_groups
        elif groups:
            del hooks[event]
    if not hooks:
        del settings["hooks"]

if changed:
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
    print(f"removed hooks from {path} (backup: {path}.tmux-claude-status.bak)")
else:
    print(f"no tmux-claude-status hooks found in {path}")
PY
else
  echo "no $SETTINGS found; skipping hook removal"
fi

# 2. Remove the source block from tmux conf. Writes through symlinks (never
#    replaces the file), so a dotfiles-symlinked ~/.tmux.conf stays a symlink.
for conf in "$HOME/.tmux.conf" "$HOME/.config/tmux/tmux.conf"; do
  [ -f "$conf" ] || continue
  python3 - "$conf" <<'PY'
import re, sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()
cleaned = re.sub(
    r"\n?# >>> tmux-claude-status >>>\n(?:.*?\n)?# <<< tmux-claude-status <<<\n?",
    "",
    content,
    flags=re.S,
)
if cleaned != content:
    with open(path, "w") as f:  # write in place: preserves symlinks
        f.write(cleaned)
    print(f"removed source block from {path}")
PY
done

# 3. Delete installed files.
for f in "$SCRIPT_DEST" "$CONF_DEST"; do
  [ -e "$f" ] && rm -f "$f" && echo "removed $f"
done

# 4. Clear live tmux state and restore the user's own config.
if command -v tmux >/dev/null && tmux ls >/dev/null 2>&1; then
  tmux set -gu @claude_status_badge 2>/dev/null
  tmux set -gu @claude_border_orig 2>/dev/null
  tmux set -gu pane-border-format 2>/dev/null
  tmux set -gu pane-border-status 2>/dev/null
  tmux list-panes -a -F '#{pane_id}' 2>/dev/null | while read -r pane; do
    tmux set -p -u -t "$pane" @claude_status 2>/dev/null
    tmux set -p -u -t "$pane" window-style 2>/dev/null
  done
  tmux list-windows -a -F '#{window_id}' 2>/dev/null | while read -r win; do
    tmux set -w -u -t "$win" window-status-style 2>/dev/null
    tmux set -w -u -t "$win" window-status-current-style 2>/dev/null
  done
  for conf in "$HOME/.tmux.conf" "$HOME/.config/tmux/tmux.conf"; do
    if [ -f "$conf" ]; then
      tmux source-file "$conf" 2>/dev/null || true
      break
    fi
  done
  echo "cleared live tmux state and re-sourced your tmux config"
fi

echo
echo "done. Running Claude Code sessions drop the hooks automatically."
