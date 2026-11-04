# OpenTofu — Proxmox

Provisions an Ubuntu 24.04 cloud-init template on Proxmox, plus (optionally) cloned VMs and LXC containers. It only provisions — software configuration (k3s, etc.) is handled by Ansible. Uses **OpenTofu** (`tofu`), not Terraform, with the [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox) provider.

## What it creates

1. Downloads the Ubuntu 24.04 (Noble) cloud image to Proxmox.
2. Uploads rendered cloud-init user-data snippets (one for the template, one per clone).
3. Creates a template VM (default ID `9000`).
4. Clones VMs from the template for every entry in `var.vms`.
5. Downloads an LXC template and creates a container for every entry in `var.lxcs`.

Cloud-init only handles OS bootstrap (users, packages, SSH hardening). Everything else is done afterwards by Ansible.

## Prerequisites

- `tofu` >= 1.6.0
- A Proxmox API token with permissions for the `tofu` user (see [scripts/setup-tofu-user-permissions.sh](../../scripts/setup-tofu-user-permissions.sh))
- A storage pool with the **snippets** content type enabled (default: `local`)
- **SSH agent loaded with a key that can log in as `root` on the Proxmox node.** The provider uses SSH (not just the API) for file uploads (`proxmox_download_file`, `proxmox_virtual_environment_file`). Verify:

  ```sh
  ssh-add -L
  ```

## Configure

```sh
cd 01-opentofu/proxmox
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`. Required values:

| Variable | Description |
| --- | --- |
| `proxmox_endpoint` | e.g. `https://192.168.1.10:8006/` |
| `proxmox_api_token` | `user@realm!tokenid=secret` |
| `ssh_public_key` | Public key contents (not a path) injected via cloud-init |
| `cloud_init_file` | `ubuntu-24.04-cloud-init.yaml` (relative to `cloud-init/`) |

Common optional values: `node_name`, `disk_storage`, `snippets_storage`, `timezone`, `bridge`.

To clone VMs, set `vms`:

```hcl
vms = {
  "server-1" = { vm_id = 1001, ansible_groups = ["k3s_server"] }
  "agent-1"  = { vm_id = 1002, max_memory = 4096, ansible_groups = ["k3s_agent"] }
}
```

Per-VM options: `cores` (2), `max_memory` (2048 MB), `min_memory` (0 MB, balloon floor; 0 disables ballooning), `disk_gb` (40), `tags`, `description` (""), `ansible_groups` ([]), `full_clone` (false).

To create LXC containers, set `lxcs`:

```hcl
lxcs = {
  "dns-1"    = { vm_id = 101, ansible_groups = ["dns"] }
  "docker-1" = { vm_id = 102, memory = 2048, disk_gb = 16, nesting = true }
}
```

Per-LXC options: `cores` (1), `memory` (512 MB), `swap` (512 MB), `disk_gb` (8), `privileged` (false), `nesting` (false), `start_on_boot` (true), `tags`, `description` (""), `ansible_groups` ([]), `mount_points` ([]), `devices` ([]). The container template is set by `lxc_template_url` / `lxc_template_file_name` and stored in `lxc_template_storage` (must allow the `vztmpl` content type). Containers get your `ssh_public_key` for root login (no cloud-init).

`mount_points` bind-mounts host directories into the container:

```hcl
"nfs-1" = { vm_id = 103, mount_points = [{ host_path = "/tank/nfs", container_path = "/srv/nfs", read_only = false }] }
```

The host directory must already exist. Proxmox only allows bind mounts when authenticated as `root@pam` (not an API token), and in unprivileged containers file ownership is shifted by 100000 (chown the host directory to match).

`devices` passes host device nodes into the container. Tailscale needs `/dev/net/tun`:

```hcl
"tailscale" = { vm_id = 111, devices = ["/dev/net/tun"] }
```

Like bind mounts, this needs `root@pam` authentication.

`description` is shown under **Notes** on the VM or container's Summary page in Proxmox. Comments in `terraform.tfvars` stay in the file and don't reach Proxmox.

> `terraform.tfvars` holds secrets. Never commit it.

## Run

```sh
tofu init       # first time only: downloads the provider
tofu validate   # must exit 0
tofu plan       # review the diff
tofu apply      # creates/updates resources — only after reviewing the plan
```

## Outputs

```sh
tofu output vm_ips      # guest-agent-reported VM IPs ("pending" until VMs boot)
tofu output lxc_ips     # LXC IPs
tofu output inventory   # host -> {ip, type (vm|lxc), groups}, for the Ansible inventory
```

## Notes

- **State is local** (`terraform.tfstate`). It is the source of truth for deployed infrastructure — do not delete, move, or overwrite it, and back it up.
- Template disk changes are ignored (`ignore_changes = [disk]`): Proxmox makes template disks read-only. Change clone disks via `vms[*].disk_gb`.
- Clone CPU/memory can be changed with `tofu apply` without a restart (hotplug enabled).
- To tear down: `tofu destroy` (destructive — confirm the plan first).
- The cloud image is pinned to a dated release with a SHA-256 checksum. To upgrade, update both `url` and `checksum` in `main.tf`.
