# Architecture

A Proxmox homelab built in three layers, each in its own numbered directory and applied in order:

```
 Proxmox host
     │  01-opentofu     tofu: cloud-init template, cloned VMs, LXCs
     ▼
 Ubuntu 24.04 VMs
     │  02-ansible      playbooks: host config, k3s + Argo CD bootstrap
     ▼
 k3s cluster ── Argo CD ◄── git (main) ── 03-argocd-kubernetes
                   │                       (watches manifests/, syncs apps/)
                   ▼
              services (MetalLB, Traefik, cert-manager, AdGuard, ...)
```

Each layer only provisions what the next one needs. OpenTofu stops at "VM with SSH access", Ansible stops at "k3s with Argo CD installed", and everything after that is reconciled by Argo CD from Git.

## Layout

| Path | Role | Notes |
|------|------|-------|
| [01-opentofu/proxmox/](01-opentofu/proxmox/) | Downloads the Ubuntu 24.04 cloud image, builds a template VM (ID 9000), clones VMs and creates LXCs | Local state. See its [README](01-opentofu/proxmox/README.md) |
| [01-opentofu/incus/](01-opentofu/incus/) | Alternative to `proxmox/`: creates VMs and containers from `images:` cloud images on Incus or IncusOS | Local state. See its [README](01-opentofu/incus/README.md) |
| [02-ansible/](02-ansible/) | Per-tool playbooks (`playbooks/<tool>/sync.yml`); `k3s-argocd` bootstraps k3s and installs Argo CD | Submodule |
| [03-argocd-kubernetes/](03-argocd-kubernetes/) | GitOps repo: `app-of-apps.yaml` plus `manifests/` and `apps/` | Submodule. See its [README](03-argocd-kubernetes/README.md) |
| [scripts/](scripts/) | One-off helpers: Proxmox user permissions, k3sup/flux bootstrap, Colima k3s node | Not part of the main flow |
| [.devcontainer/](.devcontainer/) | Dev container with the tooling (`tofu`, `kubectl`, ...) | |
| [docs/](docs/) | Conventions, e.g. [commit messages](docs/git-commit-messages.md), and [journey/](docs/journey/) write-ups of each service as it was set up, and the [plan/](docs/plan/) roadmap of future improvements | |

### 01-opentofu

- Uses the `bpg/proxmox` provider. It needs both an API token and an SSH agent, because file uploads go over SSH.
- Cloud-init (`proxmox/cloud-init/`) only does OS bootstrap: users, packages, SSH hardening.
- `terraform.tfvars` holds the VM and LXC definitions. VM IDs must be 1000 or higher and LXC IDs 100–999.
- State is local (`terraform.tfstate`) with no remote backend.

### 02-ansible

- Hosts are targeted with `-e target_hosts=<group>`. Secrets are in Ansible Vault under `group_vars/**/vault.yml`.
- `playbooks/k3s-argocd/sync.yaml` installs k3s (Traefik and servicelb disabled, since Argo CD manages them) and Argo CD via Helm.
- `playbooks/k3s-argocd/secrets.yaml` seeds the Kubernetes Secrets that must exist before External Secrets can work.

### 03-argocd-kubernetes

- `app-of-apps.yaml` is the root `Application`. It points at `manifests/`, which has one `Application` per service.
- Each `Application` consumes its config from `apps/<service>/` (Helm values, custom resources).
- Ordering is controlled by sync waves: CRDs, then operators, then ingress, then workloads. The table is in [03-argocd-kubernetes/AGENTS.md](03-argocd-kubernetes/AGENTS.md).
- **Argo CD deploys whatever is on `main`.** That is why nothing is pushed to `main` directly.

## Cross-cutting concerns

**Secrets** live in three places, depending on the layer:

| Layer | Mechanism |
|-------|-----------|
| OpenTofu | `terraform.tfvars` and `.env`, gitignored |
| Ansible | Ansible Vault (`vault.yml`), password in gitignored `.vault_pass` |
| Cluster | Bitwarden Secrets Manager, pulled by External Secrets through the `bitwarden` `ClusterSecretStore`. No `kind: Secret` is committed |

**Networking.** MetalLB hands out LAN addresses from a fixed pool. Traefik is the single HTTP/HTTPS ingress, and AdGuard Home serves DNS for `*.lan`. The authoritative list of pinned IPs is the table in [03-argocd-kubernetes/AGENTS.md](03-argocd-kubernetes/AGENTS.md), so it isn't repeated here.

**Submodules.** `02-ansible` and `03-argocd-kubernetes` are separate repos, declared in [.gitmodules](.gitmodules). Commit inside the submodule first, then record the new commit in this repo.

## Instructions for agents

Rules for working in each area live next to the code: [AGENTS.md](AGENTS.md) (root), [01-opentofu/AGENTS.md](01-opentofu/AGENTS.md), [03-argocd-kubernetes/AGENTS.md](03-argocd-kubernetes/AGENTS.md) and [.devcontainer/AGENTS.md](.devcontainer/AGENTS.md).
