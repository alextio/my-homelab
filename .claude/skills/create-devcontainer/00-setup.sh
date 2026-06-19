#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$HOME/.local/bin"
grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" \
  || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"

SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=\$HOME/.bash_history"
touch "$HOME/.bash_history"
grep -qxF "$SNIPPET" "$HOME/.bashrc" || echo "$SNIPPET" >> "$HOME/.bashrc"
