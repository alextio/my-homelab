# OpenTofu — Incus / IncusOS

Alternative to [`../proxmox/`](../proxmox/). Creates VMs and system containers on an Incus host (IncusOS or plain Incus) using the [`lxc/incus`](https://search.opentofu.org/provider/lxc/incus/latest) provider.

## How it differs from the Proxmox module

| Proxmox module | This module |
|---|---|
| `proxmox_download_file` pulls a qcow2 onto the host over SSH | `incus_image` makes Incus pull `images:ubuntu/24.04/cloud` / `images:debian/13/cloud` into its storage pool |
| Template VM (9000/9001) + clone | No templates — instances are created straight from the image |
| Cloud-init snippets uploaded to `snippets` storage | Rendered into `cloud-init.user-data` / `cloud-init.network-config` instance config keys |
| API token **and** SSH agent | Incus API with a TLS client certificate only |
| `vm_id` per VM/LXC | Instances are identified by name |
| `template = "debian"` | `os = "debian"` (or `"alma"` — Incus only, needs an x86-64-v3 host) |
| `max_memory` / `min_memory` | `memory` (no ballooning floor) |
| `dir_mappings` + `virtiofs`, `mount_points` | `storage_volumes` + `volumes` (custom volumes; virtiofs for VMs automatically) |
| `qemu-guest-agent` in cloud-init | `incus-agent` ships in the `/cloud` VM images |

The IncusOS root filesystem is read-only, but that is irrelevant here: images, instances and volumes all live in the writable (encrypted) storage pool, and everything is driven through the API.

The `inventory` output has the same shape as the Proxmox one, so Ansible works against either.

## Hardware requirements

IncusOS needs an x86-64-v3 CPU, UEFI Secure Boot and TPM 2.0 ([requirements](https://linuxcontainers.org/incus-os/docs/main/getting-started/requirements/)). The current Athlon II (x86-64-v1) can only run plain Incus on Debian; the planned i7-4790 (Haswell, v3) meets the CPU bar but the board still needs a TPM 2.0. `os = "alma"` also needs v3. See [NOTES.md](NOTES.md) for the planning notes (hardware, networking, Debian vs AlmaLinux, the Coder host).

## Auth setup

- **IncusOS:** add your client certificate (`~/.config/incus/client.crt`) to the install seed. The server then trusts it from first boot; leave `incus_trust_token` unset.
- **Plain Incus:** on the host, run `incus config trust add tofu`, put the token in `incus_trust_token` for the first `tofu apply`, then remove it.

With `generate_client_certificates = true`, the provider creates `~/.config/incus/client.{crt,key}` if they are missing.

## Usage

```sh
cp terraform.tfvars.example terraform.tfvars   # fill in values
tofu init
tofu validate
tofu plan
tofu apply                                     # only after reviewing the plan
```

Find the right `storage_pool` and `bridge` with `incus storage list` and `incus network list`. `bridge` must be a host bridge on the LAN; the default `incusbr0` is NAT-only.
