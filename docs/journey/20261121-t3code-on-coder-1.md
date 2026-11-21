# T3 Code on coder-1 and in the dev container

Installing T3 Code looked like running one playbook. In practice it meant
three things: making the server run on its own, finding that Claude Code no
longer runs on coder-1's CPU, and fixing a run of dev container problems
that stopped Ansible from starting at all.

## What we set out to do

coder-1 ([20261121-coder-1-rootless-podman-vm.md](20261121-coder-1-rootless-podman-vm.md))
is the one VM where agents work, and the phone talks to them through the
T3 Code app. The `t3code` role in `02-ansible` only installed the `t3` CLI
and the provider CLIs (Claude Code, pi). Nothing kept a server running for
the app to connect to.

Goals:
- the t3 server running on coder-1 at all times, reachable from the phone
  at home and over Tailscale
- pairing a phone from the playbook
- t3 in the dev container too, for the Mac

## Where we ended up

- **coder-1 runs `t3code.service`**, a systemd user service created by
  `t3 service install`.
  - It starts at boot and keeps running with nobody logged in (lingering).
  - It's in LAN mode: it listens on port 3773 on coder-1's LAN address.
- **Every playbook run prints a one-time pairing link and QR code**
  (`t3 pair`, valid 10 minutes). `-e t3_pair=false` skips it.
- **Providers on coder-1:**
  - pi 1.6.0
  - Claude Code **2.1.112**, pinned from npm, with its auto-updater off.
    Newer releases don't run on the Athlon II.
- **The dev container** starts `t3 serve` on every container start
  (`.devcontainer/scripts/post-start/start-t3.sh`), local-only, with no
  systemd. Its Ansible runs work again.
- **`run.sh`** works from any directory.

## Gotchas

### 1. pi didn't show up in the T3 app

pi was installed, under nvm's Node at
`~/.nvm/versions/node/v26.13.1/bin/pi`. The app didn't list it for two
reasons:

- **T3 doesn't turn Pi on by itself.** It has to be enabled in T3's
  Settings, followed by a provider refresh.
- **The server couldn't find it at first.** systemd starts user services
  with only the system directories on PATH, and t3's own `service.env`
  can't set PATH. The fix is a systemd drop-in
  (`t3code.service.d/10-path.conf`) that adds `~/.local/bin` and nvm's
  Node directory. `t3 service install` rewrites the unit file itself, so
  the drop-in is the part that survives.

### 2. Claude Code needs a newer CPU than the Proxmox host has

The installer died with "Illegal instruction" (SIGILL), the same problem
as agentgateway: the Athlon II is x86-64-v1 only. The npm package didn't
help:

- **Every release after 2.1.112 ships only a native binary.** It's
  installed through `optionalDependencies`, with no build for older CPUs.
- **2.1.112 (2026-04-16) is the last plain-JavaScript release.** It runs on
  Node anywhere.

So coder-1 pins `claude_code_npm_version: "2.1.112"`. The role installs it
from npm and sets `DISABLE_AUTOUPDATER=1` in `~/.claude/settings.json`;
otherwise Claude Code would update itself to a native build and break.

**Security:** that's seven months without Claude Code fixes, including any
to its permission checks, on the VM where agents run untrusted code. The
Proxmox firewall still keeps a compromise to coder-1 and the internet.

### 3. A new pairing code doesn't cancel the old one

`t3 pair` mints a token valid for its TTL or one use. Minting another
leaves the first one working. We tested this with two tokens and revoked
both. Paired devices keep their own sessions and are revoked separately.

Keeping several codes valid is fine here. Automatic revocation would get in
the way of a future container-based setup with more than one server.

### 4. LAN mode makes a pairing code the only lock

`T3CODE_LAN=true` makes the server listen on every interface. coder-1's
firewall doesn't filter incoming traffic, so anything on the LAN, or on the
tailnet through the subnet router, can reach port 3773 and try to pair.

A paired device gets a terminal and file access as `user`, who has sudo.
That means control of coder-1, and of the credentials stored on it, such as
the pi and Claude logins. The pairing code is also printed in the playbook
output for 10 minutes.

### 5. The dev container broke Ansible three ways

None of these were about t3, but each one stopped the playbook:

- **"could not initialize the preferred locale".** VS Code terminals
  inherit the Mac's `LANG=en_US.UTF-8`, and the Ubuntu image only has
  `C.UTF-8`. Fixed with `remoteEnv` `LANG=C.UTF-8`, which also exists on
  the Debian hosts that SSH passes `LANG` on to.
- **"Failed to create temporary directory" under `/root`.** The shells had
  `LOGNAME=root` although the user is `vscode`. Python's
  `getpass.getuser()` reads `LOGNAME` first, so Ansible's local connection
  acted as root. Fixed with `remoteEnv` `LOGNAME`/`USER=vscode`.
- **"role 't3code' was not found".** Ansible only reads `ansible.cfg` from
  the current directory, so `run.sh` from `/workspace` lost the roles path
  and inventory. `run.sh` now sets `ANSIBLE_CONFIG`.

Then nvm's arm64 Node wouldn't start without `libatomic1`, which went into
the Dockerfile.

### 6. The dev container has no systemd

Its first process is `sleep`, so `t3 service install` can't work there.
Systemd in the container is possible under rootless Podman, as root only
inside the container. It would need a Dockerfile change, `/sbin/init` as
the command, lingering, and `XDG_RUNTIME_DIR` in `remoteEnv`, and services
would lose the dev container's environment variables. We started
`t3 serve` from a post-start script instead.

### 7. Smaller ones

- **The role reinstalled t3 on every run.** The version check matched the
  "3" in "t3 v0.1.11".
- **A check for a running process matched the shell running the check.**
  `start-t3.sh` uses a pid file instead of `pgrep -f`.
- **The `nodejs` role reports changes on every run.** It did before this
  work too.

## Key decisions

| Decision | Why |
|---|---|
| Server as a systemd user service via `t3 service install` | t3's own supported mode: restarts, lingering, boot start. The role adds a PATH drop-in and `service.env` lines instead of writing its own unit. |
| `t3_service` off by default, on for coder-1 in `host_vars/coder-1/vars.yml` | On the Mac the desktop app starts its own server. |
| LAN mode on coder-1 | The phone connects directly at home and over Tailscale. Considered and not taken: T3 Connect (traffic through T3's servers, uses one of three free machines). Accepted for now: port 3773 open to the LAN, with the pairing code as the only lock. |
| `t3_pair` on by default | Each run gives a fresh code to scan. Older codes stay valid until they expire; we chose not to revoke them, so several servers can pair independently later. |
| `service.env` written one line per key | Settings that t3 writes itself (e.g. `t3 up --lan`) survive. |
| Claude Code 2.1.112 from npm on coder-1 | The only release that runs on the Athlon II. Considered and not taken: going without Claude Code until new hardware. The pin is a host var, so other hosts keep the official installer. |
| pi before claude_code in coder-1's `t3_providers` | pi pulls in the nodejs role, which the npm Claude Code needs. |
| `t3 serve` from a post-start script in the dev container, not systemd | No image or command changes. Accepted for now: nothing restarts it if it crashes. |
| Dev container server stays local-only | Anyone who pairs with it can reach what the dev container holds: the Proxmox API and Bitwarden through bws-broker, and the SSH agent that logs in to the Proxmox host as root. The phone uses coder-1 instead. |
| `remoteEnv` for `LANG`, not an `en_US` locale in the image | The rules ask to avoid Dockerfile changes, and `C.UTF-8` exists everywhere SSH passes `LANG` to. |

## Commits

`02-ansible`, branch `refactor/roles` (`1aa5e70..a0c5a58`):

| Commit | What |
|---|---|
| `04d29cd` | t3 server as a service (`t3_service`, PATH drop-in, `t3_service_env`, `t3_pair`), coder-1 host vars, version-check fix |
| `59406c3` | `claude_code_npm_version`: pinned npm Claude Code with the auto-updater off; coder-1 pins 2.1.112 |
| `a0c5a58` | `run.sh` uses the repo's `ansible.cfg` from any directory |

Parent repo, branch `feat/coder-1-agent-vm`. It's based on
`docs/plan-roadmap` (`cfead72`), and also carries the earlier coder-1 work:

| Commit | What |
|---|---|
| `3489547` | Dev container: `remoteEnv` (`LANG`, `LOGNAME`, `USER`), `libatomic1`, post-start `start-t3.sh`; also the earlier broker storage reads and `initializeCommand` |
| `9b56dbf` | OpenTofu: Debian 13 template, virtiofs mounts, the LAN-isolation firewall, the broker-check rule |
| `2a3d1e8` | Root AGENTS.md: surface security risks of proposed changes |

Left uncommitted, because it's unrelated work in the same files:
- `01-opentofu/incus/` and the Incus lines in `01-opentofu/AGENTS.md`
- `scripts/`
- the Incus row in `ARCHITECTURE.md` and the credits line in `README.md`
- Tailscale in `02-ansible` (`playbooks/tailscale/`, `requirements.yml`, its
  `CLAUDE.md` entry)

The submodule pointers aren't bumped. Both submodules point at branches
that aren't merged yet.

Done outside Git:
- `t3code.service` installed, LAN mode on, and test pairing tokens minted
  and revoked on coder-1.
- `libatomic1` installed with `sudo apt-get` in the running dev container;
  the Dockerfile has it for the next rebuild.

## Still to do

- **Rebuild the dev container and verify it** with `devcontainer up`, as
  `.devcontainer/AGENTS.md` requires. Then check `echo $LOGNAME $LANG`
  and that `start-t3.sh` ran. Not possible from inside the container.
- **Enable Pi in the T3 app** (Settings, then refresh the provider).
- **Log in to the providers on coder-1** over SSH: `pi`, then `/login`,
  and `claude auth login`.
- **Check T3 works with Claude Code 2.1.112.** T3's docs state no minimum
  version.
- **Unpin Claude Code on new hardware**: remove `claude_code_npm_version`
  from `host_vars/coder-1/vars.yml` (`02-ansible`).
- **Limit who can reach port 3773** on coder-1: an inbound rule allowing it
  only from the home subnet and the Tailscale subnet router.
- **Merge `refactor/roles`** (`02-ansible`) and `feat/coder-1-agent-vm`
  (parent), then bump the submodules.
