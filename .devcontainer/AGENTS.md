# Agent Instructions — .devcontainer

Any agent that modifies files in this directory **must** verify that the dev container builds and starts successfully before considering the task complete.

## Required verification step

After making changes to any file in `.devcontainer/`, run:

```bash
devcontainer up --workspace-folder .
```

This command must exit without error. If it fails, fix the issue before finishing.

After a successful `devcontainer up`, verify that the `vscode` user has read/write access to all named volume mount points:

```bash
devcontainer exec --workspace-folder . bash -c "
  touch /home/vscode/.claude/.writetest && rm /home/vscode/.claude/.writetest && echo '.claude OK' || echo '.claude FAILED';
"
```

Both lines must print `OK`. 

## Base image changes

When the Dockerfile `FROM` line changes to a different base image, run these steps after `devcontainer up` succeeds:

1. Wipe the stale VS Code server binaries from the named volume — the old binaries are OS-specific and will cause VS Code to fail to attach:
   ```bash
   devcontainer exec --workspace-folder . bash -c "rm -rf /home/vscode/.vscode-server"
   ```
2. Verify the `remoteUser` (`vscode`) owns its home directory and has the correct UID:
   ```bash
   devcontainer exec --workspace-folder . bash -c "id && ls -lan /home/"
   ```
   The `vscode` user must own `/home/vscode/` (same UID as the volume's file ownership). If not, the base image likely has a pre-existing user claiming UID 1000 — remove it with `userdel -r <user>` and re-create `vscode` with `-u 1000`.

## Common files and what to watch for

- **Dockerfile** — any change to base image, `RUN` steps, or `COPY` instructions can break the build. Verify layer by layer if needed.
- **devcontainer.json** — invalid JSON or unknown feature identifiers will cause `devcontainer up` to fail immediately.
- **devcontainer-lock.json** — this is auto-generated; do not edit it by hand. If it becomes stale after a `devcontainer.json` change, delete it and let `devcontainer up` regenerate it.

## Warning: features that write to `/home/vscode/` are shadowed by the volume

`devcontainer.json` mounts a named volume at `/home/vscode/`. This volume is applied **at runtime, after image build** — it replaces the entire home directory, hiding anything a devcontainer feature wrote there at build time.

**Do not rely on devcontainer features to populate the home directory.** Common examples that silently break:
- oh-my-zsh (installed by `common-utils` to `~/.oh-my-zsh`)
- dotfiles written by features to `~/.bashrc`, `~/.zshrc`, etc.
- Any feature that writes configs or tools under `~`

If a feature is needed for something other than home-directory setup (e.g., `common-utils` for `chsh`/shell default, `docker-in-docker` for the daemon), it is fine to add. But any home-directory bootstrapping that feature would have done must be reproduced in a `post-create` script, which runs after the container starts with the volume already mounted.

## Binary installation

Install binaries to `$HOME/.local/bin` (or another user-writable directory) and add it to `$PATH` in `.bashrc`. Do **not** write to `/usr/local/bin` or other root-owned paths — `postCreateCommand` runs as the `vscode` user and will fail with a permission error.

## Dockerfile

Be very reluctant to modify the Dockerfile. Prefer `post-install.sh` for tooling that changes over time (versioned CLIs, language runtimes, etc.). Only touch the Dockerfile if a dependency genuinely must be baked into the image layer (e.g., a system library that cannot be installed as a non-root user at runtime).

## Do not skip verification

Do not mark a task done based on a syntax check or linter alone. Only a successful `devcontainer up` confirms the container actually works.
