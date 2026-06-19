---
name: create-devcontainer
description: create, scaffold, or generate a devcontainer for a project; add a dev container to a repository; set up a sandbox devcontainer; initialize devcontainer files
---

Scaffold a minimal, reproducible devcontainer for any project directory. The generator
script ([.claude/skills/create-devcontainer/scaffold.sh](.claude/skills/create-devcontainer/scaffold.sh))
produces a `.devcontainer/` tree with a `debian:12-slim` base image — the smallest
glibc-compatible production image (~30 MB base, ~252 MB with dev tools) — layered with
common dev tools.

## Prerequisites

```bash
docker --version   # must be present
devcontainer --version   # must be present (npm install -g @devcontainers/cli)
```

## Run the generator

From the repo root, pass the target project directory as the first argument (default: `.`):

```bash
# scaffold into the current directory
bash .claude/skills/create-devcontainer/scaffold.sh .

# scaffold into a specific directory
bash .claude/skills/create-devcontainer/scaffold.sh path/to/project

# with extra apt packages baked into the image
bash .claude/skills/create-devcontainer/scaffold.sh . --extra-packages "age unzip"

# custom username / UID (default: vscode / 1000)
bash .claude/skills/create-devcontainer/scaffold.sh . --username dev --uid 1001
```

Output:

```
Devcontainer scaffolded in: /path/to/project/.devcontainer

.devcontainer/Dockerfile
.devcontainer/devcontainer.json
.devcontainer/scripts/post-create/00-setup.sh

Next:
  devcontainer up --workspace-folder /path/to/project
```

## Standalone Dockerfile

If you just want the Dockerfile without running the generator, copy it directly:

```bash
cp .claude/skills/create-devcontainer/Dockerfile path/to/project/.devcontainer/Dockerfile
```

The file ([.claude/skills/create-devcontainer/Dockerfile](.claude/skills/create-devcontainer/Dockerfile))
uses `vscode`/UID 1000 defaults and accepts `--build-arg USERNAME=...` / `--build-arg USER_UID=...`
to override at build time. Use `scaffold.sh` instead when you need `devcontainer.json` and
post-create scripts generated alongside it.

## What gets generated

| File | Purpose |
|---|---|
| `.devcontainer/Dockerfile` | `debian:12-slim` base + dev tools layer + non-root `vscode` user at UID 1000 |
| `.devcontainer/devcontainer.json` | Workspace bind mount, named volume for `~/`, `remoteUser: vscode`, `postCreateCommand` |
| `.devcontainer/scripts/post-create/00-setup.sh` | Creates `~/.local/bin`, adds it to `$PATH`, configures persistent bash history |

### Baked-in dev tools (apt)

`bash`, `ca-certificates`, `curl`, `git`, `gnupg`, `jq`, `openssh-client`, `sudo`, `vim`, `wget`

### Named volume for home directory

`devcontainer.json` mounts a Docker named volume at `/home/vscode/` so that anything
installed post-create (CLI tools, shell history, credentials) survives container rebuilds.
The workspace itself is a bind mount at `/workspace`.

## Verify the build

After scaffolding, verify Docker can build the image:

```bash
docker build -t my-sandbox-test path/to/project/.devcontainer \
  --build-arg USERNAME=vscode --build-arg USER_UID=1000
docker run --rm my-sandbox-test bash -c "id && git --version && curl --version | head -1"
# expected: uid=1000(vscode) ... git version 2.39.x ...
```

## Bring up the devcontainer

```bash
devcontainer up --workspace-folder path/to/project
```

Then verify volume write access:

```bash
devcontainer exec --workspace-folder path/to/project bash -c \
  "touch /home/vscode/.writetest && rm /home/vscode/.writetest && echo 'home OK'"
```

## Adding more post-create steps

Drop additional scripts in `.devcontainer/scripts/post-create/`. They run in filename
order. Name them `10-install-tools.sh`, `20-configure-shell.sh`, etc. Install binaries to
`$HOME/.local/bin` (not `/usr/local/bin` — `postCreateCommand` runs as the non-root user).

## Gotchas

- **No pre-existing UID 1000 user in debian:slim.** Unlike `ubuntu:24.04` (which ships an
  `ubuntu` user at UID 1000), `debian:12-slim` is clean — no `userdel` step needed.
- **Named volume survives `--remove-existing-container`.** Use
  `docker volume rm <name>-devcontainer-home` if you need a truly fresh home directory.
- **Base image change → stale VS Code server binaries.** After swapping the `FROM` line,
  run `devcontainer exec ... bash -c "rm -rf /home/vscode/.vscode-server"` before
  reopening in VS Code.
- **`postCreateCommand` runs as `vscode`, not root.** Anything needing root must go in the
  Dockerfile or be prefixed with `sudo` in the post-create script.
- **`--extra-packages` takes a quoted, space-separated list**, not comma-separated:
  `--extra-packages "age unzip"` (correct) vs `--extra-packages "age,unzip"` (broken).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `useradd: group 'vscode' already exists` | The base image ships a group with that name; change `--username` or remove the conflicting group in the Dockerfile |
| VS Code fails to attach after rebuild | Run `rm -rf /home/vscode/.vscode-server` inside the container — old server binaries from the previous base image are blocking the install |
| `postCreateCommand` permission denied writing to `/usr/local/bin` | Install to `$HOME/.local/bin` instead; it's on `$PATH` after `00-setup.sh` runs |
| `devcontainer up` exits with "incompatible machine config" (Podman) | Harmless Podman warning on macOS; the build still succeeds |
