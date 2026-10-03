#!/bin/bash
set -euo pipefail
MYPAD_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$HOME/.local/bin"
install -m 755 "$MYPAD_ROOT/scripts/mypad.py" "$HOME/.local/bin/mypad"
printf 'Installed %s\n' "$HOME/.local/bin/mypad"
if [[ "${1:-}" == "--skills" ]]; then
  mkdir -p "$HOME/.agents/skills/mypad"
  cp "$MYPAD_ROOT/skills/mypad/SKILL.md" "$HOME/.agents/skills/mypad/SKILL.md"
  for MYPAD_SKILLS_DIR in "$HOME/.codex/skills" "$HOME/.claude/skills" "$HOME/.pi/agent/skills"; do
    mkdir -p "$MYPAD_SKILLS_DIR"
    if [[ ! -e "$MYPAD_SKILLS_DIR/mypad" && ! -L "$MYPAD_SKILLS_DIR/mypad" ]]; then
      ln -s "$HOME/.agents/skills/mypad" "$MYPAD_SKILLS_DIR/mypad"
    fi
  done
fi
if ! command -v mypad >/dev/null; then
  printf 'Add ~/.local/bin to PATH to use mypad by name.\n'
fi
