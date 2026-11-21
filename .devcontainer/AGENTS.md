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

## Bitwarden token isolation (bws-broker)

`BWS_ACCESS_TOKEN` must never be available inside the devcontainer. `bws` here is a client for the `bws-broker` container, which holds the token (see [bws-broker/README.md](bws-broker/README.md)). Don't undo that:

- Don't add `BWS_ACCESS_TOKEN` to `containerEnv`, `remoteEnv`, `.env` files or mounts, and don't install the real `bws` CLI.
- Don't add docker-outside-of-docker or docker-in-docker, or mount a Podman/Docker socket: the first two (and a socket mount) let the devcontainer `exec` into the broker, and docker-in-docker needs `--privileged`.
- Don't widen the broker's allowlist in `bws-broker/server.py` to anything that returns secret values (`secret get`, `run`, unredacted output) or lets the client pick bws flags such as `--server-url`.
- Don't add privileges, host mounts or published ports to the `bws-broker` service in `compose.yaml`, and don't attach it to other networks.
- If `bws` reports the broker is unreachable, tell the user. Don't go looking for the token.

The broker also proxies the Proxmox API for OpenTofu on `https://bws-broker:8006/`, adding the real token from Bitwarden (see the README). The same rules apply:

- Don't put the Proxmox API token back in the devcontainer (`terraform.tfvars`, `TF_VAR_*`, env files). `terraform.tfvars` keeps a placeholder token.
- Don't widen `PVE_ALLOW`/`PVE_ALLOW_READ` or remove `PVE_DENY` entries in `server.py` to reach `/access`, `/storage` writes, consoles/shells, `execute` or guest-agent exec/file endpoints. If bpg needs a new path, allow the narrowest one and say so. The `/storage` exceptions are reads only: `GET /storage` (the listing, allowed at the user's request) and `GET /storage/<id>` (bpg reads a datastore before uploading snippets and images).
- Keep the Proxmox cert pinned (`BWS_BROKER_PVE_FINGERPRINT`); don't replace it with skipping verification.
- The broker needs outbound access to Proxmox (`192.168.4.111:8006`) as well as Bitwarden; that's expected. Still don't publish its ports or attach it to other networks.

## SELinux labels on the home volume

The host enforces SELinux, and each container run gets its own MCS categories. Files created directly under `/home/vscode` get the shared `s0` label and are fine. A file built in the container's `/tmp` and then `mv`'d into the home volume keeps `/tmp`'s per-container label. The next recreated container then gets "Permission denied" running, replacing or deleting it, even though `vscode` owns it (this broke `uv`, via astral's `install.sh`). So:

- In `post-create` scripts, write binaries straight into `~/.local/bin` (`tar -x -C`, `curl -o`, `install`), not through an installer that stages in `/tmp` and `mv`s.
- `:z` on the volume mount doesn't fix files that are already mislabelled. Don't disable SELinux labelling (`security_opt: label=disable`) to work around it: that removes SELinux confinement from the whole devcontainer.
- Check with `ls -Z`. A stuck file can only be removed from the host: `podman unshare rm <volume mountpoint>/<path>`.

The devcontainer is defined in `compose.yaml` (not `build`/`runArgs` in `devcontainer.json`). Its compose provider must be podman-compose, so run `devcontainer up` with `--docker-path podman --docker-compose-path podman-compose`. The home volume is pinned to the name `my-homelab-devcontainer`; keep it, or the existing home directory is lost.

## `remoteEnv` in devcontainer.json

- `LANG=C.UTF-8`: VS Code terminals otherwise inherit the Mac's `en_US.UTF-8`, which the image doesn't have, and Ansible refuses to start ("could not initialize the preferred locale").
- `LOGNAME`/`USER=vscode`: the shells otherwise get `LOGNAME=root`. Python's `getpass.getuser()` reads `LOGNAME` first, so Ansible's local connection acts as root and fails on `/root/.ansible/tmp`.

## post-start scripts

`postStartCommand` runs every `scripts/post-start/*.sh` on each container start. Unlike post-create, a failing script is reported but doesn't stop the container. There's no systemd in the container, so long-running processes are started with `setsid nohup … &` and a pid file (see `start-t3.sh`), and nothing restarts them if they exit.

## Tailscale

The phone reaches the dev container's T3 Code server over the tailnet.
`post-create/install-tailscale.sh` installs a pinned, checksum-verified
Tailscale. `post-start/start-tailscale.sh` runs `tailscaled` as `vscode` in
userspace-networking mode, with its state and socket in
`~/.local/share/tailscale`. The `~/.local/bin/tailscale` wrapper points the
CLI at that socket.

- **The only way in is `tailscale serve`.** `t3 pair --tailscale` publishes
  t3 (still bound to 127.0.0.1:3773) on HTTPS 443. Don't publish anything
  else.
- **Keep userspace mode.** Don't add `/dev/net/tun`, `NET_ADMIN`, or
  `--socks5-server` / `--outbound-http-proxy-listen`. In userspace mode
  without those, programs here can't open connections into the tailnet or
  through the subnet router.
- **Log in without routes or DNS:**
  `tailscale up --hostname=homelab-devcontainer --accept-routes=false --accept-dns=false`.
- **For now the node is untagged, and the tailnet policy is unchanged**
  (we plan to move to Headscale). So the node gets the rules that apply to
  your own devices. With an allow-all policy, every tailnet device can reach
  HTTPS 443, with the t3 pairing code as the only lock. The node key also
  expires every 180 days. Restricting it to the phone is a policy change on
  the control plane, not something to set here:
  ```jsonc
  "tagOwners": { "tag:devcontainer": ["autogroup:admin"] },
  "hosts":     { "phone": "100.x.y.z" },
  "grants": [
    // ...existing grants, none matching tag:devcontainer...
    { "src": ["phone"], "dst": ["tag:devcontainer"], "ip": ["tcp:443"] },
  ],
  "tests": [
    { "src": "phone", "accept": ["tag:devcontainer:443"] },
  ],
  ```
  Then log in again with `--advertise-tags=tag:devcontainer --force-reauth`.
- **Treat `~/.local/share/tailscale` as a key.** It holds the node key, so
  anyone who copies it can join the tailnet as this node.
- **HTTPS needs MagicDNS and HTTPS certificates** turned on for the
  tailnet. The certificate for `homelab-devcontainer.<tailnet>.ts.net` goes
  into public Certificate Transparency logs.

## Binary installation

Install binaries to `$HOME/.local/bin` (or another user-writable directory) and add it to `$PATH` in `.bashrc`. Do **not** write to `/usr/local/bin` or other root-owned paths — `postCreateCommand` runs as the `vscode` user and will fail with a permission error.

## Dockerfile

Be very reluctant to modify the Dockerfile. Prefer `post-install.sh` for tooling that changes over time (versioned CLIs, language runtimes, etc.). Only touch the Dockerfile if a dependency genuinely must be baked into the image layer (e.g., a system library that cannot be installed as a non-root user at runtime).

## Do not skip verification

Do not mark a task done based on a syntax check or linter alone. Only a successful `devcontainer up` confirms the container actually works.
