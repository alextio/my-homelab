#!/usr/bin/env bash
# Starts tailscaled on every container start, so the phone can reach the
# T3 Code server over the tailnet. Installed by post-create/install-tailscale.sh.
#
# Userspace networking: no tun device or extra privileges. Nothing in the
# container gets a tailnet address or routes; the only way in is what
# `tailscale serve` publishes (t3 on HTTPS 443, set up by `t3 pair --tailscale`).
# Which devices may connect is decided by the tailnet policy, not here: see
# "Tailscale" in .devcontainer/AGENTS.md. Like start-t3.sh, nothing restarts
# it if it exits; run this script again.
set -euo pipefail

LIB="$HOME/.local/lib/tailscale"
STATE="$HOME/.local/share/tailscale"
SOCK="$STATE/tailscaled.sock"
PIDFILE="$STATE/tailscaled.pid"
LOG="$STATE/tailscaled.log"
TS="$HOME/.local/bin/tailscale"

if [[ ! -x "$LIB/tailscaled" || ! -x "$TS" ]]; then
  echo "Tailscale isn't installed; skipping (.devcontainer/scripts/post-create/install-tailscale.sh)"
  exit 0
fi

# The state directory holds the node key: whoever copies it is this node.
mkdir -p "$STATE"
chmod 700 "$STATE"

if [[ -s "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null \
  && tr '\0' ' ' <"/proc/$(cat "$PIDFILE")/cmdline" | grep -q 'tailscaled'; then
  echo "tailscaled is already running (pid $(cat "$PIDFILE"))"
else
  rm -f "$SOCK"
  # No --socks5-server or --outbound-http-proxy-listen: without them,
  # programs in the container can't open connections into the tailnet.
  setsid nohup "$LIB/tailscaled" \
    --tun=userspace-networking \
    --statedir="$STATE" \
    --socket="$SOCK" \
    >>"$LOG" 2>&1 </dev/null &
  echo $! >"$PIDFILE"
  echo "tailscaled started (pid $!); log: $LOG"
fi

for _ in $(seq 20); do
  [[ -S "$SOCK" ]] && break
  sleep 0.5
done

state="$("$TS" status --json 2>/dev/null | jq -r '.BackendState' || true)"
case "$state" in
  Running)
    echo "Tailscale is connected as $("$TS" status --json | jq -r '.Self.DNSName')"
    ;;
  NeedsLogin|NoState|"")
    cat <<'EOF'
Tailscale isn't logged in yet. Run (see "Tailscale" in .devcontainer/AGENTS.md):
  tailscale up --hostname=homelab-devcontainer --accept-routes=false --accept-dns=false
  t3 pair --tailscale     # publishes t3 on HTTPS 443 and prints a pairing link
EOF
    ;;
  *)
    echo "Tailscale state: $state (tailscale status for details)"
    ;;
esac
