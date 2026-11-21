# Coder workspaces as k3s pods, then switched off

The Podman-over-SSH setup felt brittle, so Coder workspaces moved into the
cluster as pods on a dedicated, tainted node. It worked. Then pushing the
first template showed what Coder templates can and can't do from a phone,
and the whole approach was set aside. It stays in Git, scaled to zero.

## What we set out to do

The starting point was [20261119-coder-podman-host-over-ssh.md](20261119-coder-podman-host-over-ssh.md):
Coder in k3s, starting containers on `coder-1` over SSH.

The first idea was to split the work into two composable Coder templates:
one to create the VM if it's missing, one to start containers on it. That
didn't work out:

- **Coder templates can't depend on each other.** Each workspace is one
  Terraform run.
- **A template that creates VMs needs the Proxmox token.** It would sit
  inside Coder.
- **External provisioners are a Premium feature.** That's the way to run
  Terraform somewhere other than inside the Coder server, closer to the
  infrastructure.
- **A provisioner VM wasn't an option.** There isn't the RAM for a second
  always-on VM.

The new goal: run workspaces as pods, isolated enough to run agents' code,
without a second VM.

## Where we ended up

- **`coder-1` as a k3s agent node.** It joined with the `agent-token`, not
  the server token. Its taint and label `coder-workspaces=true` keep every
  other workload off it.
- **A `coder-workspaces` namespace** with:
  - `restricted` Pod Security
  - a default-deny NetworkPolicy: no ingress; egress only to DNS, the Coder
    pods on 8080, and the internet minus every private range
- **Coder's ServiceAccount** can manage pods and Deployments only in
  `coder-workspaces`, and no longer in its own namespace.
- **A `kubernetes` Coder template** in `apps/coder/templates/`. Argo CD
  skips that folder; the template is pushed with `coder templates push`.
  - a Deployment and PVC per workspace
  - pinned to the workspace node
  - no ServiceAccount token
  - non-root
- **Then switched off,** on branch `chore/coder-scale-to-zero` (pushed, not
  merged):
  - `coder.replicaCount: 0`
  - `coder-1` left the cluster and became a standalone VM
  - the docs describe how to bring a node back

## Gotchas

### 1. Coder's limits showed up only after we'd built it

We found these only after the template was in, by trying to use it:

- **A workspace is whatever the template says.** There's no way to start an ad-hoc
  container for a new repo from the UI. Anything a workspace needs (repos,
  tools, images) has to be a template parameter or baked into an image.
- **One template run, one workspace.** Several agent containers mean several
  workspaces, each with its own PVC.
- **Getting into a workspace from the T3 Code app on a phone** needs Coder's
  SSH proxying (`coder ssh` / `coder config-ssh`), not plain SSH to a host.

These should have been raised when pods were first proposed. The
"Surface security risks" section in [AGENTS.md](../../AGENTS.md) covers
security only; usability limits matter just as much before building.

### 2. A k3s node can't set its own taint

The NodeRestriction admission plugin stops a kubelet from changing its own
taints after it registers. The taint has to come from the node's
registration flags (`node-taint` in its k3s config) or from an admin. That
also means a compromised workspace node can't remove it.

### 3. The agent token is not the server token

A k3s server's `token` lets the holder join as a **server**, with the full
datastore. `agent-token` only lets a node join as an agent. `k3s-server-1`
had no separate agent token, so one was added to
`/etc/rancher/k3s/config.yaml`. A backup is at `config.yaml.bak-20261120`.

### 4. The Kubernetes provider sends `runAsNonRoot: false`

The `hashicorp/kubernetes` provider writes `runAsNonRoot=false` in the
container's securityContext unless it's set explicitly, which overrides the pod-level
`true`. Restricted Pod Security then rejects the pod. The fix is to set
`run_as_non_root = true` at both levels.

### 5. Pushing a template needs a Coder role

`coder templates push` failed with `rbac: forbidden`:

- `alex` signs in through Dex (OIDC) and had no roles.
- The only owner was `a`, a dummy account from setup.

The fix was `coder users edit-roles` to make `alex` an owner. To suspend
`a`, take away its owner role first: Coder won't suspend an owner.

### 6. Smaller ones

- **Removing a node doesn't stick while its agent runs.** k3s-agent
  re-registers it. Stop it with `systemctl disable --now k3s-agent`, then
  delete the node.
- **Rejoining under the same name fails** until `<name>.node-password.k3s`
  is deleted on the server.
- **Argo CD multi-source revision fields** are empty until a sync finishes.
  A wait loop has to read `syncResult.revisions[1]`.
- **Provisioner tags `<none>`** just means the built-in provisioner, which
  runs inside the Coder server.

## Key decisions

| Decision | Why |
|---|---|
| Pods on a tainted node, not the SSH-to-Podman VM | One control plane, and Kubernetes' own isolation: Pod Security, NetworkPolicy, scoped RBAC. No SSH key that unlocks a host. |
| Considered and not taken: composable VM + container templates | Coder templates can't depend on each other, and a VM template would need the Proxmox token inside Coder. |
| Considered and not taken: an external provisioner on a VM | Premium only, and there isn't the RAM for another always-on VM. |
| `restricted` Pod Security, no ServiceAccount token, default-deny egress to private ranges | A workspace runs untrusted code. It shouldn't reach the Kubernetes API, the LAN or the other services, only the internet and Coder. |
| Coder's own namespace off its workspace permissions | A compromised template can't create pods next to Coder's database credentials. |
| Templates in `apps/coder/templates/`, excluded from Argo CD | They're Terraform for Coder, not manifests. Keeping them next to the app keeps them findable. |
| Scale Coder to zero rather than delete it | We want to try Coder again later. The template, namespace and policies stay in Git; only `replicaCount` changes. |
| Remove `coder-1` from the cluster | A standalone VM is simpler for one big workspace, and a node that runs agents shouldn't hold cluster credentials. |

## Commits

`03-argocd-kubernetes`, on `main`:

| Commit | What |
|---|---|
| `eb465d8` (PR #5) | `coder-workspaces` namespace, restricted Pod Security, NetworkPolicy, Coder's RBAC moved to that namespace, SSH ExternalSecret and ConfigMap removed |
| `c9eeef3` (PR #6) | `kubernetes` workspace template and README, `templates/*` excluded from the Coder Application |

Branch `chore/coder-scale-to-zero`, pushed and not merged
(`4faead4..f5e02a8`):

| Commit | What |
|---|---|
| `a8b6058` | `coder.replicaCount: 0` |
| `f5e02a8` | coder-1 dropped as the workspace node, and from the IP table; how to rejoin a node |

Outside Git:
- `agent-token` in `k3s-server-1:/etc/rancher/k3s/config.yaml`.
- `alex` made an owner in Coder.
- The `coder-1` node deleted from the cluster.

## Still to do

- **Merge `chore/coder-scale-to-zero`.** Until then Coder still runs.
- **Suspend or delete Coder's `a` account** if it isn't done yet.
- **If Coder comes back:**
  - a workspace node needs `node-taint` / `node-label` in its k3s config,
    and its old `.node-password.k3s` entry deleted
  - `templates push` needs a Coder owner or template-admin
