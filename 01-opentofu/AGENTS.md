# Agent Instructions — opentofu

This directory provisions a Proxmox homelab using **OpenTofu**. Ubuntu 24.04 cloud-init templates and VM clones are the primary resources.

## Critical rules

### Never apply infrastructure changes without explicit confirmation
Do not run `tofu apply`, `tofu destroy`, or any command that mutates live Proxmox state unless the user has explicitly asked you to run it in this session. Propose the plan first.

### Use `tofu`, not `terraform`
This repo uses OpenTofu. The binary is `tofu`. Do not substitute `terraform`.

### Never commit secrets
`.env` files, API tokens, SSH private keys, and `terraform.tfvars` files with real values must never be staged or committed. Check `git diff --cached` before any commit.

### Never delete or overwrite state files
`proxmox/terraform.tfstate` and `terraform.tfstate.backup` are the source of truth for deployed infrastructure. Do not delete, move, or overwrite them. State is local — there is no remote backend.

### SSH agent must be loaded before tofu runs
The `bpg/proxmox` provider uses SSH (not just the API token) for file transfer operations (`proxmox_download_file`, `proxmox_virtual_environment_file`). Both auth paths are required. Verify with `ssh-add -L` before running `tofu apply`.

## Verification after tofu changes

After any change to `proxmox/` or `proxmox/cloud-init/`:

1. Run `tofu validate` — must exit 0.
2. Run `tofu plan` — review the diff before applying.
3. Do not mark a task complete based on a lint/format check alone.

## Proxmox ID ranges
- LXC containers (`lxcs` in `proxmox/terraform.tfvars`) must use `vm_id` **100–999**.
- VMs (`vms`) must use `vm_id` **1000 or higher**.
- When adding or editing examples, docs, or tfvars, keep IDs inside these ranges. Do not pick an ID outside the range for the resource type.
- The template VM (`template_vm_id`, default 9000) is the one existing exception.
