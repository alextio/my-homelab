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
  KIND_VERSION="${KIND_VERSION:-0.32.0}"
  KIND_URL="https://github.com/kubernetes-sigs/kind/releases/download/v${KIND_VERSION}/kind-linux-${TARGETARCH}"
  KIND_SHA256="$(curl -fsSL "${KIND_URL}.sha256sum" | cut -d' ' -f1)"
  curl -fsSL "$KIND_URL" -o "$HOME/.local/bin/kind"
  echo "${KIND_SHA256}  $HOME/.local/bin/kind" | sha256sum -c - \
    || { rm -f "$HOME/.local/bin/kind"; exit 1; }
  chmod +x "$HOME/.local/bin/kind"
fi

# install the bws client. It forwards to the bws-broker container, which holds
# BWS_ACCESS_TOKEN; the real bws CLI and the token never enter this container.
# Always reinstalled so it replaces a real bws left in the home volume.
install -m 755 "$(dirname "$0")/../../bws-broker/bws" "$HOME/.local/bin/bws"

# install uv (also manages its own Python; the image has none)
# Extracted straight into ~/.local/bin, not via astral's install.sh: that
# script unpacks in the container's /tmp and mv's the binaries over, which
# keeps /tmp's per-container SELinux label, so the next (recreated) container
# can't run, replace or delete them ("Permission denied").
if ! uv --version &>/dev/null 2>&1; then
  UV_VERSION="${UV_VERSION:-0.13.9}"
  UV_TARBALL="uv-${ARCH}-unknown-linux-gnu.tar.gz"
  UV_URL="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/${UV_TARBALL}"
  mkdir -p "$HOME/.cache"
  UV_SHA256="$(curl -fsSL "${UV_URL}.sha256" | cut -d' ' -f1)"
  curl -fsSL "$UV_URL" -o "$HOME/.cache/${UV_TARBALL}"
  echo "${UV_SHA256}  $HOME/.cache/${UV_TARBALL}" | sha256sum -c -
  tar -xzf "$HOME/.cache/${UV_TARBALL}" -C "$HOME/.local/bin" --strip-components=1 \
    || { echo "uv: cannot write ~/.local/bin/uv; if it has a stale SELinux label (ls -Z), delete it from the host" >&2; exit 1; }
  rm -f "$HOME/.cache/${UV_TARBALL}"
fi
export PATH="$HOME/.local/bin:$PATH"

# install python3 (uv-managed, user-space). --default also links python,
# python3 and python3.X into ~/.local/bin. Idempotent: a no-op when present.
PYTHON_VERSION="${PYTHON_VERSION:-3.13}"
uv python install "$PYTHON_VERSION" --default --preview-features python-install-default

# install Ansible
# Not the devcontainers-extra ansible feature: it pip-installs pipx into the
# system Python, which Ubuntu 24.04 blocks (PEP 668).
# ansible-core provides the CLIs (ansible-playbook, ansible-galaxy,
# ansible-vault); the `ansible` package adds the community collections.
# Python is pinned: uv otherwise picks the newest (3.15), which ansible-core
# 2.22 doesn't support (AttributeError on dataclasses._is_type at startup).
# --force replaces a broken install instead of skipping it.
ANSIBLE_PYTHON="${ANSIBLE_PYTHON:-3.13}"
if ! ansible --version &>/dev/null 2>&1; then
  uv tool install --force --python "$ANSIBLE_PYTHON" ansible-core --with ansible
fi
if ! ansible-lint --version &>/dev/null 2>&1; then
  uv tool install --force --python "$ANSIBLE_PYTHON" ansible-lint
fi
