# Coder workspaces on a Podman VM, reached over SSH

The first try at a VM for coding agents: Coder (in k3s) would start
workspace containers on a separate Debian VM through rootless Podman. It
worked end to end, but it was dropped a day later
([20261120-coder-workspaces-as-k3s-pods.md](20261120-coder-workspaces-as-k3s-pods.md)).
Most of what lasted came from getting OpenTofu through the broker safely.

## What we set out to do

Coder already ran in k3s (`apps/coder`). The goal was a Proxmox VM to hold
every Podman container used for agentic development, with Coder starting
them. Incus was out of scope: the homelab is still on Proxmox.

The constraint was isolation. Agents run untrusted code, so the cluster
shouldn't hand Coder a path to anything more than "run containers on that
VM".

## Where we ended up

- `coder-1`: Debian 13 VM 1003, 192.168.6.103, 4 cores, 4–12 GiB RAM, a
  150 GB disk, cloned from the Debian template by OpenTofu.
- Rootless Podman on it (the `podman-docker` playbook), plus a dedicated
  `coder` user with no sudo and a locked password.
- Coder's pod reached it as `ssh://coder-1`, with a key that only works:
  - from the k3s node's IP (`from="192.168.6.101"`)
  - for `podman system dial-stdio` (`command=`)
  - with no PTY or port forwarding (`restrict`)
- The key and `known_hosts` came from Bitwarden through an ExternalSecret,
  mounted at `/home/coder/.ssh` together with an `ssh_config`.
- The broker can now read storage definitions, and a new rule in
  [01-opentofu/AGENTS.md](../../01-opentofu/AGENTS.md) says to check the
  broker's allowlist before every `tofu apply`.
- The dev container rebuilds the broker image on every rebuild
  (`initializeCommand`), under a fixed compose project name, `my-homelab`.

All of the Coder side was undone the next day; see "Still to do".

## Gotchas

### 1. A clean `tofu plan` doesn't mean the apply gets through the broker

`bws-broker` is the dev container's proxy to the Proxmox API. It holds the
real token and forwards only an allowlist of paths. `tofu plan` makes only
read calls, so it passed. The apply then:

1. deleted two cloud-init snippets (files on the Proxmox host that
   cloud-init reads at boot), to replace them, and
2. failed on `GET /storage/local`, which the broker refused. bpg reads the
   datastore before it uploads a file.

`k3s-server-1` would not have booted without those snippets. We restored
them by hand over SCP, rendering each one byte for byte with `tofu console`
and checking the md5 against `templatefile`. The first try had broken the
indentation.

This became the standing rule: before every apply, list the API calls each
planned action makes, from the bpg source for the pinned version, and check
them against `PVE_ALLOW` / `PVE_ALLOW_READ` / `PVE_DENY`.

### 2. An unrelated snippet edit would have replaced `k3s-server-1`

An uncommitted virtiofs `mounts` change in the Ubuntu cloud-init file
changed its snippet's ID. bpg treats that as "replace the VM". Both
templates and every clone now have `ignore_changes` on
`initialization[0].user_data_file_id`. To apply a snippet change we now
replace the VM on purpose: `tofu apply -replace='…vm["<name>"]'`.

### 3. A broker "rebuild" kept running the old code

Recreating the containers reused the old broker image. That's why
`initializeCommand` now builds `bws-broker` on the host first. Its `-p` must
match the `name: my-homelab` in `compose.yaml`, or the new image gets a
different name and isn't used.

**Security:** `initializeCommand` runs on the host, as us, on every
open. Anything that can edit `devcontainer.json` can run code there, so
review `git diff .devcontainer` before rebuilding. The bws-broker README
says so.

### 4. Pod traffic arrives from the node's IP

k3s source-NATs pod traffic leaving the cluster to the node IP, so
`from="192.168.6.101"` lets any pod on that node use the key, not just
Coder. The key itself is the real gate: it sits in one Secret in the `coder`
namespace.

### 5. Becoming an unprivileged user needs `acl`

Ansible's `become_user: coder` failed with
`chmod: invalid mode: A+user:coder:rx:allow` until the `acl` package was
installed. Then `--check` failed on a fresh host before `acl` was there, so
the check-mode guard had to wait for every package.

### 6. Smaller ones

- **OpenSSH and a root-owned 0444 key.** OpenSSH only rejects a key with
  loose permissions when the running user owns it, so a projected volume
  (root-owned, `defaultMode 0444`) works.
- **No Reloader opt-in.** A projected volume updates in place, and ssh
  re-reads the files on every connection.
- **The Coder chart's resource defaults.** Requests equal limits
  (2 CPU / 4 GiB), so a second pod never fit on the 4-CPU node and rollouts
  stuck in Pending. Requests went down to 250m / 1 GiB; the limits stayed.

## Key decisions

| Decision | Why |
|---|---|
| Debian 13 VM, rootless Podman | Fits the x86-64-v1 host. Rootless keeps a container escape at an unprivileged user. |
| A `coder` user from Ansible, not cloud-init | Ansible already owns software on the VM, and that account's key and options change with the cluster. |
| A restricted `authorized_keys` line instead of an open socket | Exposes only the Podman API, only to the k3s node, with no shell or forwarding. A TCP socket would have been open to the whole LAN. |
| Key in Bitwarden, delivered by an ExternalSecret (`CreatedOnce`) | Keeps it out of Git. The private key was shredded locally and on the node after it was uploaded. |
| Broker allows `GET /storage` and `GET /storage/<id>`, nothing else under `/storage` | bpg reads a datastore before uploads. Proxmox leaves stored passwords and keys out of these responses. Writes stay refused. |
| Restore the snippets by hand rather than widen the broker mid-apply | Got `k3s-server-1` safe first, without changing the security boundary under pressure. |

## Commits

`03-argocd-kubernetes`, on `main` via PR #4:

| Commit | What |
|---|---|
| `73e4ba8` | `coder-ssh` ExternalSecret, `coder-ssh-config` ConfigMap, the SSH mount, lower Coder requests, coder-1 in the IP table |

Reverted by `eb465d8` (PR #5) the next day.

Parent repo, on branch `feat/coder-1-agent-vm` (committed later, with the
rest of the coder-1 work):

| Commit | What |
|---|---|
| `3489547` | The broker storage reads, `initializeCommand` and `name: my-homelab` (with the later dev container fixes) |
| `9b56dbf` | The broker rule in `01-opentofu/AGENTS.md`, `ignore_changes` in `main.tf`, the coder-1 example in `terraform.tfvars.example` (with the Debian template and the firewall) |

`02-ansible`: the EL + Debian `podman-docker` playbook with service users
was never committed. It was trimmed to Debian only before the first commit
([20261121-coder-1-rootless-podman-vm.md](20261121-coder-1-rootless-podman-vm.md)).

Outside Git:
- The two snippets restored over SCP.
- The `coder-ssh-private-key-b64` and `coder-ssh-known-hosts` secrets in
  Bitwarden.

## Still to do

- **Delete the two Bitwarden secrets.** Nothing reads them since PR #5, and
  the `coder` user they unlocked went away when coder-1 was recreated.
- **Coder's HTTPRoute showed OutOfSync** in Argo CD after the merge. It
  wasn't checked whether that was already the case before.
