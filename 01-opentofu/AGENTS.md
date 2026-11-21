# Agent Instructions — opentofu

This directory provisions the homelab using **OpenTofu**. `proxmox/` targets the current Proxmox host; `incus/` is an alternative module for Incus or IncusOS (see [incus/README.md](incus/README.md)). In `proxmox/`, cloud-init templates (Ubuntu 24.04 by default, plus Debian 13) and VM clones are the primary resources. Each VM picks its OS with `vms[*].template` (`"ubuntu"` or `"debian"`), which selects both the template it clones and its cloud-init file.

The Proxmox host is an AMD Athlon II (x86-64-v1 only: no SSSE3/SSE4.1/SSE4.2). Don't add templates or recommend VM images that need x86-64-v2 or newer (RHEL/Alma/Rocky 9+, CentOS Stream 9+), or container base images built on them (UBI 9).

## Critical rules

### Never apply infrastructure changes without explicit confirmation
Do not run `tofu apply`, `tofu destroy`, or any command that mutates live Proxmox or Incus state unless the user has explicitly asked you to run it in this session. Propose the plan first.

### Check the broker allows every API call before `tofu apply` (proxmox/ only)
In the devcontainer, OpenTofu reaches Proxmox through `bws-broker`, which only forwards an allowlist of API paths (`PVE_ALLOW`, `PVE_ALLOW_READ` and `PVE_DENY` in [../.devcontainer/bws-broker/server.py](../.devcontainer/bws-broker/server.py)). `tofu plan` only makes read calls, so a clean plan doesn't prove the apply will get through. Before every `tofu apply`, list the API calls the planned create/update/delete actions make (from the `bpg/proxmox` source for the pinned version) and check each against the allowlist. If one is refused, stop and tell the user before applying; don't apply and find out halfway.

**Why:** an apply that hit the broker's `/storage` refusal had already deleted two cloud-init snippets and couldn't re-upload them, leaving `k3s-server-1` unable to boot until they were restored by hand.

### Use `tofu`, not `terraform`
This repo uses OpenTofu. The binary is `tofu`. Do not substitute `terraform`.

### Never commit secrets
`.env` files, API tokens, SSH private keys, and `terraform.tfvars` files with real values must never be staged or committed. Check `git diff --cached` before any commit.

### Never delete or overwrite state files
`proxmox/terraform.tfstate`, `incus/terraform.tfstate` and their `.backup` files are the source of truth for deployed infrastructure. Do not delete, move, or overwrite them. State is local — there is no remote backend.

### SSH agent must be loaded before tofu runs (proxmox/ only)
The `bpg/proxmox` provider uses SSH (not just the API token) for file transfer operations (`proxmox_download_file`, `proxmox_virtual_environment_file`). Both auth paths are required. Verify with `ssh-add -L` before running `tofu apply`.

## Verification after tofu changes

After any change to `proxmox/`, `incus/` or their `cloud-init/` directories:

1. Run `tofu validate` — must exit 0.
2. Run `tofu plan` — review the diff before applying.
3. Do not mark a task complete based on a lint/format check alone.

## Proxmox ID ranges (proxmox/ only)
- LXC containers (`lxcs` in `proxmox/terraform.tfvars`) must use `vm_id` **100–999**.
- VMs (`vms`) must use `vm_id` **1000 or higher**.
- When adding or editing examples, docs, or tfvars, keep IDs inside these ranges. Do not pick an ID outside the range for the resource type.
- The template VMs (`template_vm_id`, default 9000; `debian_template_vm_id`, default 9001) are the one existing exception.

## Incus module (`incus/`)
- Uses the `lxc/incus` provider over the Incus API with a TLS client certificate. No SSH agent is needed.
- Instances are identified by name; there is no `vm_id` and the ID ranges above don't apply.
- Each instance picks its OS with `os` (`"ubuntu"`, `"debian"` or `"alma"`), which selects both the `images:` cloud image and the cloud-init file.
- Keep the `inventory` output the same shape as `proxmox/`'s, so Ansible works against either module.
- `incus/` targets the planned replacement host, an i7-4790 (Haswell, x86-64-v3), so `os = "alma"` (AlmaLinux 10) is allowed there. The Athlon II note above still applies to `proxmox/` and to the current host. IncusOS also needs UEFI Secure Boot and TPM 2.0; see [incus/NOTES.md](incus/NOTES.md).
