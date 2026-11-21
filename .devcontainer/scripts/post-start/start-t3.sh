#!/usr/bin/env bash
# Starts the T3 Code server (`t3 serve`) in the background on every container
# start. There's no systemd here, so nothing restarts it if it exits; run this
# script again. It answers on the container's 127.0.0.1:3773 only (forward the
# port in VS Code to use it from the Mac). Log, including the pairing link:
# ~/.t3/serve.log. t3 itself is installed by 02-ansible (./run.sh t3code).
set -euo pipefail

T3="$HOME/.local/bin/t3"
LOG="$HOME/.t3/serve.log"
PIDFILE="$HOME/.t3/serve.pid"

if [[ ! -x "$T3" ]]; then
  echo "t3 isn't installed; skipping (02-ansible: ./run.sh t3code)"
  exit 0
fi

if [[ -s "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null \
  && tr '\0' ' ' <"/proc/$(cat "$PIDFILE")/cmdline" | grep -q 't3 serve'; then
  echo "t3 serve is already running (pid $(cat "$PIDFILE"))"
  exit 0
fi

# The providers (pi, and Node for it) live under nvm, which only interactive
# shells load.
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
[[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
export PATH="$HOME/.local/bin:$PATH"

mkdir -p "$(dirname "$LOG")"
# The log holds the pairing token.
touch "$LOG" && chmod 600 "$LOG"
# setsid + nohup: survive the end of the postStartCommand exec session.
cd "$HOME"
setsid nohup "$T3" serve >>"$LOG" 2>&1 </dev/null &
echo $! >"$PIDFILE"
echo "t3 serve started (pid $!); log: $LOG"
