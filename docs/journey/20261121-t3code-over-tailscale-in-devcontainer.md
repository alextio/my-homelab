# T3 Code from the phone to the dev container, over Tailscale

We wanted the T3 Code app on the phone to reach the dev container as well
as coder-1. That meant running Tailscale inside a container that has no
systemd, no tun device and no extra privileges, and deciding how much to
lock down now when the control plane will probably change.

## What we set out to do

The dev container already started `t3 serve` on every start
([20261121-t3code-on-coder-1.md](20261121-t3code-on-coder-1.md)), but only on
the container's 127.0.0.1. The phone is on the tailnet, and the dev
container runs in Podman's VM on the Mac, so nothing on the phone could
reach it.

Constraints:
- **No new container privileges,** published ports, or socket mounts.
  `.devcontainer/AGENTS.md` forbids those, because they would weaken the
  bws-broker isolation.
- **The t3 server stays off the LAN.**
- **No changes to the tailnet's access policy for now.** We expect to
  replace Tailscale with Headscale, a self-hosted control server, and
  didn't want to tune a policy we'll throw away.

## Where we ended up

- **`post-create/install-tailscale.sh`** installs Tailscale 1.104.7,
  pinned and checksum-verified, into `~/.local/lib/tailscale`. A wrapper,
  `~/.local/bin/tailscale`, points the CLI at the per-user daemon's socket.
- **`post-start/start-tailscale.sh`** runs `tailscaled` as `vscode` in
  userspace-networking mode on every start. Its state and socket are in
  `~/.local/share/tailscale` (mode 700).
- **The node:**
  - named `homelab-devcontainer`, logged in as our own user, untagged
  - no subnet routes, no tailnet DNS
  - node key expires 2027-05-20
- **`tailscale serve`** publishes
  `https://homelab-devcontainer.<tailnet>.ts.net` (tailnet only) to
  `http://127.0.0.1:3773`. `t3 pair --tailscale` set it up, and it
  persists in tailscaled's state on the home volume.
- **The phone (iOS) is paired.** Its T3 session lasts until 2026-12-21 and
  renews with use.

## Gotchas

### 1. Locking it to the phone is a control-plane job

The plan was "only the phone may connect". Nothing inside the container can
enforce that:
- Tailscale's access rules live in the tailnet policy.
- `tailscale serve` forwards any connection the policy allows.
- T3 doesn't check which device a connection comes from.

The policy route needs a tag (`tag:devcontainer` with a `tagOwners` entry)
and a grant from the phone's address to that tag. The first login with
`--advertise-tags=tag:devcontainer` failed with "requested tags
[tag:devcontainer] are invalid or not permitted", because the policy
didn't declare the tag yet.

So the node is untagged for now. **Security:** it gets the same rules as
our other devices. If the policy is still allow-all, every tailnet device
can reach HTTPS 443 on it, and the T3 pairing code is the only lock. These
are our own devices, plus the subnet router, so the risk is moderate. The
policy snippet to fix it is in `.devcontainer/AGENTS.md`.

### 2. Userspace mode is what keeps the container contained

Kernel-mode Tailscale needs `/dev/net/tun` and `NET_ADMIN`. Userspace mode
needs neither, and it has two useful side effects:
- **Nothing in the container gets a tailnet address,** so the only way in
  is what `tailscale serve` publishes.
- **Without `--socks5-server` or `--outbound-http-proxy-listen`, programs
  in the container can't open connections into the tailnet or through the
  subnet router.** The `tailscale` CLI itself still can (`tailscale nc`).

### 3. The daemon's socket isn't where the CLI looks

`tailscaled` runs as `vscode`, so its socket can't be in
`/var/run/tailscale`. Both our commands and t3's `t3 pair --tailscale`
call plain `tailscale`, so a wrapper in `~/.local/bin` adds
`--socket=$HOME/.local/share/tailscale/tailscaled.sock`. With the CLI
talking to a daemon owned by the same user, t3 didn't need Tailscale's
"operator" permission.

### 4. `t3 pair --tailscale`, not `t3 serve --tailscale-serve`

T3's docs list both. `t3 serve --tailscale-serve` starts a new server,
which would collide with the one `start-t3.sh` already runs on 3773.
`t3 pair --tailscale` is for a running server: it adds the Serve mapping and
prints a pairing link on the `ts.net` name. The server itself stays on
127.0.0.1, with no `--lan`.

### 5. Smaller ones

- **A cancelled tagged login left a stale login URL.** Running `tailscale
  up --reset` with the untagged flags started a fresh login.
  `tailscaled` keeps waiting for a login after the CLI times out, so the
  URL stays valid.
- **HTTPS on `ts.net` needs MagicDNS and HTTPS certificates** on the
  tailnet. These are DNS settings, not access rules. The certificate's
  name is in public Certificate Transparency logs.
- **SELinux:** extracting the tarball straight into the home volume
  (`tar -x -C`) gives the binaries the shared `s0` label, so a recreated
  container can still run them.

## Key decisions

| Decision | Why |
|---|---|
| Tailscale inside the dev container, userspace mode | No privileges, devices, published ports or socket mounts, so the bws-broker isolation rules hold. Considered and not taken: forwarding 3773 out through Podman's VM and the Mac (opens it to the LAN, needs the Mac's firewall changed), and T3 Connect (traffic through T3's servers). |
| t3 stays on 127.0.0.1, published only by `tailscale serve` on HTTPS 443 | One way in, over WireGuard and TLS. Nothing on the LAN can reach it. |
| Untagged node, no policy change | Headscale will replace the control plane, so tuning Tailscale's policy now is wasted work. Accepted for now: any tailnet device can try to pair, and the node key expires every 180 days. |
| Pinned Tailscale tarball with a SHA-256 check | Same pattern as the other post-create installs. The checksum comes from the same release server, so it catches a corrupt download, not a compromised release. |
| Daemon state in `~/.local/share/tailscale` on the home volume | The login and the Serve mapping survive rebuilds. **Security:** the directory holds the node key; anyone who copies it is this node. |

**Blast radius, unchanged by the choices above:** a paired device gets a
terminal in the dev container as `vscode`, who has passwordless sudo. From
there it can reach the Proxmox API and Bitwarden through bws-broker, and the
SSH agent while it's loaded, which logs in to the Proxmox host as root. A
lost phone with an active session is a path to the hypervisor. Revoke it in
T3 (Settings → Sharing & access, or `t3 auth session revoke <id>`) and in
the Tailscale admin console.

## Commits

Parent repo, branch `feat/coder-1-agent-vm`:

| Commit | What |
|---|---|
| `cbd1caf` | `install-tailscale.sh`, `start-tailscale.sh` and the Tailscale section in `.devcontainer/AGENTS.md` |

This write-up and the roadmap update are the commit after it.

Done outside Git:
- Tailscale installed in the running dev container and logged in as
  `homelab-devcontainer`.
- `tailscale serve` mapping 443 → 127.0.0.1:3773, added by
  `t3 pair --tailscale`.
- The phone paired with T3.

## Still to do

- **Restrict the node to the phone.** Tag it (`tag:devcontainer`) and add a
  grant from the phone's tailnet address only, with `tests`, in the
  Tailscale policy, or the equivalent in Headscale once we've moved. The
  snippet is in `.devcontainer/AGENTS.md`.
- **Log in again before 2027-05-20**, when the untagged node key expires.
  Tagging it ends the expiry.
- **Verify on a rebuild** that the post-create and post-start scripts run
  from `devcontainer up`, along with the earlier dev container checks.
