#!/usr/bin/env bash
set -euo pipefail

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) TARGETARCH="amd64" ;;
  aarch64|arm64) TARGETARCH="arm64" ;;
  *) echo "Unsupported arch: $ARCH" && exit 1 ;;
esac

mkdir -p "$HOME/.local/bin"
grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" \
  || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"

# install OpenTofu
TOFU_VERSION="${TOFU_VERSION:-1.12.1}"
curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${TARGETARCH}.tar.gz" \
  | tar -xz -C "$HOME/.local/bin" tofu
chmod +x "$HOME/.local/bin/tofu"

# install Claude Code
curl -fsSL https://claude.ai/install.sh | bash

# install kubectl
KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
  -o "$HOME/.local/bin/kubectl"
chmod +x "$HOME/.local/bin/kubectl"
