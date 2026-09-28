# Agent Instructions — homelab

This repo provisions a Proxmox homelab using **OpenTofu** (not Terraform) with a GitOps workflow. Ubuntu 24.04 cloud-init templates and VM clones are the primary resources.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the repository layout.

## Critical rules

### Never apply infrastructure changes without explicit confirmation
Do not run `tofu apply`, `tofu destroy`, or any command that mutates live Proxmox state unless the user has explicitly asked you to run it in this session. Propose the plan first.

### Use `tofu`, not `terraform`
This repo uses OpenTofu. The binary is `tofu`. Do not substitute `terraform`.

### Never commit secrets
`.env` files, API tokens, SSH private keys, and `terraform.tfvars` files with real values must never be staged or committed. Check `git diff --cached` before any commit.

### Never delete or overwrite state files
`infrastructure/proxmox/terraform.tfstate` and `terraform.tfstate.backup` are the source of truth for deployed infrastructure. Do not delete, move, or overwrite them. State is local — there is no remote backend.

### SSH agent must be loaded before tofu runs
The `bpg/proxmox` provider uses SSH (not just the API token) for file transfer operations (`proxmox_download_file`, `proxmox_virtual_environment_file`). Both auth paths are required. Verify with `ssh-add -L` before running `tofu apply`.

## Verification after tofu changes

After any change to `infrastructure/proxmox/` or `cloud-init/`:

1. Run `tofu validate` — must exit 0.
2. Run `tofu plan` — review the diff before applying.
3. Do not mark a task complete based on a lint/format check alone.

## Dev container changes

See [.devcontainer/AGENTS.md](.devcontainer/AGENTS.md) for rules that apply when editing `.devcontainer/` files.

## Git Commit Messages

See [.docs/git-commit-messages.md](docs/git-commit-messages.md).