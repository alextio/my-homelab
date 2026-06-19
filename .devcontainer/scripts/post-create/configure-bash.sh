#!/usr/bin/env bash
set -euo pipefail

BASHRC="$HOME/.bashrc"

if grep -q 'parse_git_branch' "$BASHRC" 2>/dev/null; then
  exit 0
fi

cat >> "$BASHRC" <<'EOF'

# Colored prompt: virtualenv | user@host:dir (git-branch) $
__venv_ps1() {
  [ -n "${VIRTUAL_ENV:-}" ] && echo "($(basename "$VIRTUAL_ENV")) "
}
__git_ps1_simple() {
  local b
  b=$(git symbolic-ref --short HEAD 2>/dev/null) || return
  echo " ($b)"
}
PS1='\[\033[0;35m\]$(__venv_ps1)\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[01;33m\]$(__git_ps1_simple)\[\033[00m\]\$ '
EOF
