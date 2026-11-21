# coder-1 as a plain rootless Podman VM

After the Coder experiments, the plan became one VM with one big workspace,
where several agent threads run side by side. The `podman-docker` playbook
had grown to cover EL, service users and a rootful socket, so it was cut
back to what that VM needs, and the VM was rebuilt from scratch.

## What we set out to do

`coder-1` was still a k3s agent node from
[20261120-coder-workspaces-as-k3s-pods.md](20261120-coder-workspaces-as-k3s-pods.md).
The goal was a plain Debian VM with rootless Podman working as a Docker
drop-in for `user`: the `docker` command, `docker compose`, and a socket for
tools that expect Docker.

The playbook also had to follow the repo's rules: it passes `--check` on a
fresh host, and Galaxy is checked before writing tasks by hand.

## Where we ended up

- `coder-1` recreated with `tofu apply -replace`: Debian 13, same VM ID 1003
  and IP 192.168.6.103, no k3s.
- The `podman-docker` playbook, Debian only:
  - `podman`, `podman-docker` (the `docker` CLI shim), `uidmap`, `passt`,
    `dbus-user-session`
  - a rootless API socket for `user`, with linger, exported as
    `DOCKER_HOST` in `~/.config/shell.d/podman-docker.sh`
  - `podman-restart.service`, so containers with restart policies come back
    after a reboot
  - `docker.io` for short image names
  - Docker's Compose **v5.8.0** from GitHub, checksum-verified, in the CLI
    plugin directory, plus a `docker-compose` symlink. Debian's
    `docker-compose` package is removed.
- It's idempotent on coder-1 and passes `--check`. It has since moved
  into `roles/podman_docker`, and the Compose commit was made on top of
  that.

## Gotchas

### 1. No Galaxy role fits

We wanted an official Podman role rather than our own tasks. The candidates:

- **`containers.podman`** is a collection of modules, not a role that sets
  up rootless Podman as a Docker drop-in.
- **`linux-system-roles.podman`** manages containers and quadlets. It
  doesn't install the Docker shim or Compose, or set up the user socket the
  way this needs.

So we kept plain tasks, trimmed: keep the `docker` alias, Compose
and the socket; drop EL, service users and the rootful socket.

### 2. Debian's Compose is years old

Debian 13 ships `docker-compose` 2.26 (version string `2.26.1-4`, with no
`v2.` prefix, which broke the first version check). Podman also looks in
`/usr/libexec` first, so it would pick the old one even with a newer binary
on PATH. The package is now removed, and the release binary from GitHub
goes into `/usr/local/lib/docker/cli-plugins`, checked against the
release's own `.sha256`.

### 3. The user session's D-Bus wasn't running on the first run

Ansible's SSH login started `user`'s systemd instance before `dbus-user-session`
was installed. `systemctl --user` then failed. The fix: `daemon_reload` and
start `dbus.socket` before the Podman units.

### 4. Smaller ones

- **Draining the node first wasn't needed.** Nothing but DaemonSets ran on
  the tainted node.
- **Deleting the node didn't stick at first.** The running `k3s-agent`
  re-registered it until it was disabled.
- **The new VM has a new SSH host key.** It was checked against
  `qm guest exec` output before it went into `known_hosts`.
- **ansible-lint's `partial-become`** needs `become: true` next to every
  `become_user`.

## Key decisions

| Decision | Why |
|---|---|
| One VM, one workspace, several agent threads | Simpler than per-repo containers, and works with T3 Code over plain SSH. Coder stays in Git for later. |
| Recreate the VM rather than clean up k3s | The OpenTofu module was up to date, and a fresh clone guarantees no k3s leftovers or cluster credentials. |
| Plain tasks, not a Galaxy role | No role covers the Docker shim, Compose and the user socket (gotcha 1). |
| Rootless only, no `/run/docker.sock` | A container escape lands as `user`, not root. The agents get sudo on the VM anyway, so the real boundary is the Proxmox firewall ([20261121-lan-isolation-firewall-for-coder-1.md](20261121-lan-isolation-firewall-for-coder-1.md)). |
| Compose from GitHub, pinned and checksum-verified | Current Compose without adding Docker's apt repo. The checksum comes from the same release, so it catches a corrupt download, not a compromised release. |

## Commits

`02-ansible`. Commits from separate work are interleaved on
`refactor/roles` (the roles refactor `a71df57`, t3code, bws), so these are
the two from this work:

| Commit | Branch | What |
|---|---|---|
| `86f0c7b` | `feat/argocd-install-only`, now in `refactor/roles` | Debian-only rootless Podman playbook, coder-1 in `[podman_docker]` |
| `1aa5e70` | `refactor/roles` | Compose v5.8.0 from GitHub, Debian's package removed; CLAUDE.md and README entries |

Outside Git: `coder-1` recreated (`-replace`) and the playbook applied.

## Still to do

- **Merge `refactor/roles`** in `02-ansible`, and bump the submodule in the
  parent repo.
- **On coder-1, not done yet:**
  - the homelab CA
  - the default tools: node, Python with uv, Go, Rust, Claude Code, pi,
    Chromium with Playwright
  - T3 Code (`roles/t3code`)
- **Later:** point Claude Code and pi at agentgateway, so no API tokens live
  on the VM.
