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

grep -qxF 'export PATH="$HOME/.cargo/bin:$PATH"' "$HOME/.bashrc" \
  || echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/.cargo/bin:$PATH"

# install OpenTofu
if ! tofu --version &>/dev/null 2>&1; then
  TOFU_VERSION="${TOFU_VERSION:-1.12.1}"
  curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${TARGETARCH}.tar.gz" \
    | tar -xz -C "$HOME/.local/bin" tofu
  chmod +x "$HOME/.local/bin/tofu"
fi

# install Claude Code
if ! claude --version &>/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh | bash
fi

# install kubectl
if ! kubectl version --client &>/dev/null 2>&1; then
  KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
    -o "$HOME/.local/bin/kubectl"
  chmod +x "$HOME/.local/bin/kubectl"
fi

# install k9s
if ! k9s version &>/dev/null 2>&1; then
  curl -fsSL "https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_${TARGETARCH}.tar.gz" \
    | tar -xz -C "$HOME/.local/bin" k9s
  chmod +x "$HOME/.local/bin/k9s"
fi

# install argocd CLI
if ! argocd version --client &>/dev/null 2>&1; then
  curl -fsSL "https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-${TARGETARCH}" \
    -o "$HOME/.local/bin/argocd"
  chmod +x "$HOME/.local/bin/argocd"
fi

# install helm
if ! helm version &>/dev/null 2>&1; then
  HELM_VERSION="${HELM_VERSION:-3.19.0}"
  curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" \
    | tar -xz -C "$HOME/.local/bin" --strip-components=1 "linux-${TARGETARCH}/helm"
  chmod +x "$HOME/.local/bin/helm"
fi

# install cargo-binstall
if ! cargo-binstall --version &>/dev/null 2>&1; then
  curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash
fi

# install forgejo-cli
if ! fj --version &>/dev/null 2>&1; then
  cargo-binstall forgejo-cli
fi

# install kind 
if ! kind version &>/dev/null 2>&1; then
  echo "Installing kind..."
  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.32.0/kind-linux-${TARGETARCH}
  chmod +x ./kind
  sudo mv ./kind /usr/local/bin/kind
fi