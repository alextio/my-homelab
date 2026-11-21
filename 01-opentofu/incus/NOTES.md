# Notes: moving to Incus / IncusOS

Working notes from planning the Proxmox → Incus move. Nothing here is decided except where marked.

## Hardware

- **Planned host:** Intel i7-4790 (Haswell). *Confirm the model: "i7-4970" doesn't exist.* Haswell is **x86-64-v3**, which IncusOS and AlmaLinux 10 both need. The current Athlon II (x86-64-v1) can run neither, only plain Incus on Debian.
- IncusOS also needs **UEFI Secure Boot** and **TPM 2.0** ([requirements](https://linuxcontainers.org/incus-os/docs/main/getting-started/requirements/)).
  - Z97/H97-era boards generally have UEFI Secure Boot.
  - TPM 2.0 is the open question. Look for Intel PTT (the firmware TPM) in the BIOS, or a TPM header that takes a plug-in module.
  - Without TPM 2.0, IncusOS has a reduced-security mode (Secure Boot on, no TPM; [docs](https://linuxcontainers.org/incus-os/docs/main/reference/installing-without-tpm/)). Secure Boot itself is always required.
- After the hardware swap, update the CPU note in [../AGENTS.md](../AGENTS.md).

## Images on a read-only OS

The IncusOS root filesystem is read-only, but that doesn't matter here. Images, instances and volumes live in the writable, encrypted storage pool, and everything is driven through the Incus API, with no shell or SSH on the host.

- Incus pulls images itself from `images:`. The `/cloud` variants ship with cloud-init, and the VM images also include `incus-agent`.
- Cloud-init is passed as instance config keys (`cloud-init.user-data`, `cloud-init.network-config`). There are no template VMs, clones or snippet uploads.
- Custom images, such as an official upstream qcow2, can still be imported over the API (`incus image import`, or `incus_image.source_file`).

## Bridged vs NAT networking

`incusbr0`, the default network, is a private virtual network inside the host. Instances get `10.x` addresses from Incus's DHCP, and outbound traffic is NAT'd behind the host's IP. Nothing on the LAN can connect *in* without port forwards.

The homelab needs instances to be real LAN hosts: static `192.168.4.x` addresses, SSH from Ansible, MetalLB IPs, and AdGuard serving DNS. So the NIC uses `nictype = bridged` on a host bridge attached to the physical NIC, which is what `vmbr0` is on Proxmox. That bridge is the `bridge` variable.

## Debian 13 vs AlmaLinux 10

| | Debian 13 (trixie) | AlmaLinux 10 |
|---|---|---|
| Lineage | Community, independent | A rebuild of RHEL 10 |
| Support | About 5 years (to about 2030, including LTS) | About 10 years (security fixes to about 2035) |
| Upgrades | Major release every ~2 years; you upgrade yourself | Minor releases every 6 months through `dnf update`; a major upgrade about once a decade |
| Kernel | 6.12 LTS | 6.12 with Red Hat backports |
| Packages | `apt`, huge main repo | `dnf`; extras such as `htop` need EPEL (and sometimes CRB) |
| Security | AppArmor | SELinux enforcing |
| Firewall | None by default | firewalld (if installed) |
| Automatic updates | `unattended-upgrades` | `dnf-automatic` |
| Incus image | `images:debian/13/cloud` | `images:almalinux/10/cloud` |

How this plays out for the stack:

- **k3s:** fine on both. Alma adds `k3s-selinux`, and firewalld fights Flannel and MetalLB (k3s recommends disabling it). Debian has neither issue.
- **Podman:** Alma's strong point. Red Hat develops it, and Quadlet and SELinux labels are first-class. Debian's version is a bit behind.
- **NVIDIA:** Alma ships pre-signed NVIDIA modules, which work under Secure Boot as-is. Debian builds the driver with DKMS and needs a MOK enrolled, or `security.secureboot=false` on that VM. This matters because Incus VMs boot with Secure Boot by default.
- **Ansible:** Debian's strong point. The playbooks use `ansible.builtin.apt`. Alma means rewriting package and repo tasks, plus SELinux and firewalld handling. Ubuntu-specific spots to fix for Debian:
  - `02-ansible/playbooks/docker/sync.yml` (Docker apt repo URL)
  - `02-ansible/playbooks/shell/templates/00-common.sh.j2` (`distribution == 'Ubuntu'` branch)
  - `02-ansible/playbooks/dns/sync.yml` (systemd-resolved stub listener)
- **Docs:** most homelab guides assume Debian/Ubuntu.

**Leaning:** Debian 13 for the general fleet, especially the k3s nodes. It's the boring choice, and the existing Ansible mostly works. Alma for hosts where it has a clear advantage, which mixing distros under Incus makes cheap. The cost of each extra distro is Ansible upkeep.

**Consolidation:** drop Ubuntu in favour of Debian 13 for the general fleet. In `proxmox/`, that replaces existing Ubuntu VMs, so review the `tofu plan` first.

## AlmaLinux VM for Coder workspaces (decided: wanted either way)

The VM runs `os = "alma"` with [cloud-init/almalinux-10-cloud-init.yaml](cloud-init/almalinux-10-cloud-init.yaml) (example `coder-1` in `terraform.tfvars.example`).

How the pieces connect: the Coder server (e.g. in k3s) runs a template that uses the Docker provider with `host = "ssh://user@coder-1"`. Docker on the VM runs the workspace containers. Each workspace's Coder agent dials *out* to the Coder access URL, so the VM needs no inbound ports beyond SSH.

What goes where:

- **Cloud-init (done):** OS bootstrap only.
  - The `user` account in `wheel`, key-only SSH via an `sshd_config.d` drop-in.
  - EPEL and CRB enabled.
  - `dnf-automatic` applying security updates.
  - SELinux left enforcing.
- **Ansible (decided: Podman, not Docker CE):** `02-ansible/playbooks/podman-docker/sync.yml`, targeting the `podman_docker` group. It sets Podman up as a Docker drop-in:
  - The `podman-docker` shim provides the `docker` CLI.
  - Each user in `podman_rootless_users` gets a rootless API socket, with linger enabled. The Coder template reaches it with `host = "ssh://user@coder-1"`. This works because `docker system dial-stdio` maps to `podman system dial-stdio`.
  - A rootful socket sits behind `/run/docker.sock` for tools that hardcode that path. It's root-only unless `podman_docker_group_members` is set.
  - Docker Compose v2 is the compose provider, so `docker compose`, `podman compose` and `docker-compose` all work.
  - `docker.io` is the short-name registry, and `podman-restart.service` restarts `--restart=always` containers after a reboot.
- **Known differences from real Docker:**
  - Rootless and rootful containers are separate: `docker ps` and `sudo docker ps` show different sets.
  - Bind mounts under SELinux need `:Z` or `:z`. Named volumes are labelled automatically.
  - Rootless containers can't bind host ports below 1024 by default.
  - Coder templates that need privileged containers (docker-in-docker, envbox) need the rootful socket.
- **Sizing:** rootless images and volumes live under `~user/.local/share/containers`, and rootful ones under `/var/lib/containers`. Give the VM a large `disk_gb` (100 GiB in the example) or attach a `storage_volumes` volume there.

## Open items

- [ ] Confirm the CPU model, and that the board has TPM 2.0 (PTT or a module).
- [ ] Pick the fleet OS (leaning Debian 13), then consolidate both modules.
- [ ] Find the LAN bridge name on the new host (`incus network list`).
- [x] Write the Ansible playbook for the Coder host (`podman-docker`). It has passed lint and syntax checks but hasn't been run against a real AlmaLinux host yet.
- [ ] Run `--check --diff`, then apply on `coder-1`, and point a Coder Docker template at it.
- [ ] Update the CPU note in `../AGENTS.md` after the hardware swap.
