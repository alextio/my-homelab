#!/usr/bin/env bash
# Scaffold a minimal devcontainer in TARGET_DIR (default: current directory).
# Usage: bash scaffold.sh [TARGET_DIR] [--username NAME] [--uid UID] [--extra-packages "pkg1 pkg2"]
set -euo pipefail

TARGET="."
USERNAME="vscode"
USER_UID=1000
EXTRA_PACKAGES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --username) USERNAME="$2"; shift 2 ;;
    --uid)      USER_UID="$2"; shift 2 ;;
    --extra-packages) EXTRA_PACKAGES="$2"; shift 2 ;;
    -*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *)  TARGET="$1"; shift ;;
  esac
done

DEVCONTAINER_DIR="$TARGET/.devcontainer"
SCRIPTS_DIR="$DEVCONTAINER_DIR/scripts/post-create"
mkdir -p "$SCRIPTS_DIR"

# --- Dockerfile ---
EXTRA_PKG_LINES=""
if [[ -n "$EXTRA_PACKAGES" ]]; then
  for pkg in $EXTRA_PACKAGES; do
    EXTRA_PKG_LINES+="    ${pkg} \\"$'\n'
  done
fi

cat > "$DEVCONTAINER_DIR/Dockerfile" <<DOCKERFILE
FROM debian:12-slim

ARG USERNAME=${USERNAME}
ARG USER_UID=${USER_UID}
ARG USER_GID=\$USER_UID

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \\
    bash \\
    ca-certificates \\
    curl \\
    git \\
    gnupg \\
    jq \\
    openssh-client \\
    sudo \\
    vim \\
    wget \\
${EXTRA_PKG_LINES}    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid \$USER_GID \$USERNAME \\
    && useradd -m --uid \$USER_UID --gid \$USER_GID -s /bin/bash \$USERNAME \\
    && echo "\$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/\$USERNAME \\
    && chmod 0440 /etc/sudoers.d/\$USERNAME

WORKDIR /workspace
USER \$USERNAME
DOCKERFILE

# --- devcontainer.json ---
WORKSPACE_BASENAME=$(basename "$(realpath "$TARGET")")
cat > "$DEVCONTAINER_DIR/devcontainer.json" <<JSON
{
  "name": "\${localWorkspaceFolderBasename}",
  "build": {
    "dockerfile": "Dockerfile",
    "context": ".."
  },
  "workspaceMount": "source=\${localWorkspaceFolder},target=/workspace,type=bind",
  "mounts": [
    "source=\${localWorkspaceFolderBasename}-devcontainer-home,target=/home/${USERNAME}/,type=volume"
  ],
  "workspaceFolder": "/workspace",
  "remoteUser": "${USERNAME}",
  "postCreateCommand": "for f in .devcontainer/scripts/post-create/*.sh; do bash \"\$f\"; done",
  "shutdownAction": "stopContainer"
}
JSON

# --- post-create: PATH + history ---
cat > "$SCRIPTS_DIR/00-setup.sh" <<'SETUP'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$HOME/.local/bin"
grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" \
  || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"

SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=\$HOME/.bash_history"
touch "$HOME/.bash_history"
grep -qxF "$SNIPPET" "$HOME/.bashrc" || echo "$SNIPPET" >> "$HOME/.bashrc"
SETUP
chmod +x "$SCRIPTS_DIR/00-setup.sh"

echo ""
echo "Devcontainer scaffolded in: $(realpath "$DEVCONTAINER_DIR")"
echo ""
find "$DEVCONTAINER_DIR" -type f | sort | sed "s|$(realpath "$TARGET")/||"
echo ""
echo "Next:"
echo "  devcontainer up --workspace-folder $TARGET"
