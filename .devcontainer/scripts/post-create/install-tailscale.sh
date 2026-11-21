#!/usr/bin/env bash
# Installs Tailscale (tailscale + tailscaled) into ~/.local/lib/tailscale,
# pinned and checksum-verified, plus a `tailscale` wrapper in ~/.local/bin
# that talks to the per-user daemon's socket. post-start/start-tailscale.sh
# runs the daemon in userspace-networking mode (no /dev/net/tun, no extra
# container privileges). To update: bump TS_VERSION and both checksums from
# https://pkgs.tailscale.com/stable/tailscale_<version>_<arch>.tgz.sha256
set -euo pipefail

TS_VERSION="1.104.7"
declare -A TS_SHA256=(
  [amd64]="e56693ff74a64f2591b7e819c280635a100aae1ddfb0ef058fcd052b7cd8d16c"
  [arm64]="d6bed2720310b328b861f943d7b4016c5358a9bad60575eb51e8143b79068484"
)

case "$(uname -m)" in
  x86_64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "Unsupported arch: $(uname -m)" && exit 1 ;;
esac

LIB="$HOME/.local/lib/tailscale"
if [[ -x "$LIB/tailscaled" ]] && "$LIB/tailscale" version 2>/dev/null | head -1 | grep -qx "$TS_VERSION"; then
  exit 0
fi

tgz="$(mktemp)"
trap 'rm -f "$tgz"' EXIT
curl -fsSL -o "$tgz" "https://pkgs.tailscale.com/stable/tailscale_${TS_VERSION}_${ARCH}.tgz"
echo "${TS_SHA256[$ARCH]}  $tgz" | sha256sum -c --quiet -

# Extract straight into the home volume (see "SELinux labels" in AGENTS.md).
mkdir -p "$LIB" "$HOME/.local/bin"
tar -xzf "$tgz" -C "$LIB" --strip-components=1 \
  "tailscale_${TS_VERSION}_${ARCH}/tailscale" "tailscale_${TS_VERSION}_${ARCH}/tailscaled"

# The daemon runs as vscode with its socket in the home directory, so every
# `tailscale` call (yours, and t3's for `t3 pair --tailscale`) needs --socket.
cat >"$HOME/.local/bin/tailscale" <<'EOF'
#!/bin/sh
exec "$HOME/.local/lib/tailscale/tailscale" --socket="$HOME/.local/share/tailscale/tailscaled.sock" "$@"
EOF
chmod +x "$HOME/.local/bin/tailscale"
echo "Tailscale $TS_VERSION installed"
