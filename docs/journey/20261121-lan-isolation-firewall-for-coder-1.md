# A Proxmox firewall that keeps coder-1 off the LAN

Agents on `coder-1` run with sudo, so nothing inside the VM can be trusted
to enforce egress rules. They live on the Proxmox host instead. Testing them
showed that the one cluster path they allow, agentgateway, had been dead for
weeks, so its proxy was scaled to zero.

## What we set out to do

`coder-1` ([20261121-coder-1-rootless-podman-vm.md](20261121-coder-1-rootless-podman-vm.md))
runs coding agents with sudo. We wanted its outgoing traffic kept away from
the cluster's services, with model traffic eventually going only through
agentgateway. At first we planned to allow Traefik too, then dropped it:
Traefik fronts every `*.lan` service.

Incoming traffic stays open for now, because we SSH in from both the LAN and
Tailscale.

## Where we ended up

- [01-opentofu/proxmox/firewall.tf](../../01-opentofu/proxmox/firewall.tf)
  sets this up for any VM with `lan_isolated = true`:
  - the datacenter firewall switched on, with every policy ACCEPT
  - a cluster IP set `private`: RFC 1918, CGNAT/Tailscale, link-local,
    multicast, IPv6 ULA and multicast
  - per-VM outbound rules: the `lan_isolated_allow` entries, then DROP to
    `+dc/private`
  - IP and MAC filtering, so the VM can't switch to another address
- **`lan_isolated_allow`** (in `variables.tf`) allows only:
  - DNS to AdGuard Home in k3s (192.168.6.201)
  - HTTPS to agentgateway (192.168.6.202)
- **coder-1 uses 192.168.6.201 for DNS** (new `dns_servers` option).
- **Checked after a reboot:**
  - Reachable: DNS, GitHub and the internet.
  - Blocked: Traefik on 80 and 443, the AdGuard UI, the k3s API, node SSH,
    Proxmox on 8006, the router and 10.0.0.1.
- **The agentgateway proxy** is set to zero replicas on branch
  `chore/agentgateway-scale-to-zero` (pushed, not merged). The controller
  keeps running.

## Gotchas

### 1. The datacenter switch affects the whole host

Proxmox only runs guest firewalls while the datacenter firewall is on. Its
default input policy is DROP, which only accepts the host's own subnet, and
that can lock us out of the web UI and SSH from elsewhere. The datacenter
resource sets every policy to ACCEPT, so turning it on changes nothing for
the host or for any VM without its own firewall.

### 2. `*.lan` names resolve differently on the two AdGuards

The adguard-1 LXC (192.168.6.2) resolved `agentgateway.lan` to Traefik
through its `*.lan` wildcard. The k3s AdGuard resolves it to 192.168.6.202.
With Traefik blocked, coder-1 has to use the k3s AdGuard. We have since shut
adguard-1 down.

### 3. A full plan would have restarted adguard-1

`terraform.tfvars` still says adguard-1 should be running, so a plain
`tofu apply` would have started the LXC we had just shut down. The
apply ran from a saved plan targeted at the firewall resources and
`vm["coder-1"]`.

### 4. Changing DNS gives the VM a new host key

Proxmox derives the cloud-init instance ID from its settings, so a new DNS
server looks like a new instance. On the next boot cloud-init regenerates
the SSH host keys. The new key was checked against `qm guest exec` before it
went into `known_hosts`.

### 5. agentgateway had been crash-looping all along

The one allowed cluster address answered nothing from anywhere, not just
from coder-1. Its proxy pod was in CrashLoopBackOff with SIGILL (an illegal
CPU instruction). The proxy image needs x86-64-v2, and the host's Athlon II
only supports x86-64-v1.

The controller generates the proxy Deployment from the Gateway, so scaling
the Deployment by hand would be reverted. The fix is an
`AgentgatewayParameters` resource with `deployment.spec.replicas: 0`,
referenced from the Gateway's `infrastructure.parametersRef`.

### 6. Smaller ones

- **`tofu plan` timed out once** on "Could not read directory mapping
  nas-personal/nas-media". A retry worked.
- **Replies need no inbound rules.** Replies to allowed connections pass
  through conntrack, which tracks open connections.

## Key decisions

| Decision | Why |
|---|---|
| Rules on the Proxmox host, not in the VM | Agents have sudo and could change any firewall inside the VM. |
| Block every private range, then allow by exception | Covers the LAN, the cluster's Service and LoadBalancer IPs, Tailscale and IPv6, without listing each host. |
| `ipfilter` and `macfilter` on | Otherwise sudo could change the VM's IP or MAC and get around per-address rules. |
| No Traefik in the allowlist | Traefik fronts every `*.lan` service, so allowing it opens all of them. |
| Only agentgateway reaches the cluster | One audited path for model access. Nothing else in the cluster is reachable. |
| Considered and not taken: a forward proxy like bws-broker | Wait until the simple firewall proves too coarse. |
| Inbound left open for now | We SSH in from both the LAN and Tailscale. **Risk:** anything on the LAN can reach every port the VM listens on. |
| Scale the agentgateway proxy via `AgentgatewayParameters` | Survives the controller reconciling the Deployment, and comes back by deleting one line. |

**Not covered:** traffic inside a Tailscale tunnel running on the VM. The
host only sees encrypted packets, so the tailnet ACL decides. Don't run
`tailscaled` on coder-1 without an ACL that matches these rules.

## Commits

`03-argocd-kubernetes`, branch `chore/agentgateway-scale-to-zero`, pushed and
not merged (`4faead4..73f5aa6`):

| Commit | What |
|---|---|
| `73f5aa6` | `AgentgatewayParameters` with zero replicas, the Gateway's `parametersRef`, the IP table row |

Parent repo, branch `feat/coder-1-agent-vm`:

| Commit | What |
|---|---|
| `9b56dbf` | `firewall.tf`; `dns_servers`, `lan_isolated` and `lan_isolated_allow` in `variables.tf`; the `dns` block and `firewall` on `network_device` in `main.tf`. Also the Debian template and virtiofs mounts, which were uncommitted in the same files. |

`terraform.tfvars` is gitignored: `dns_servers` and `lan_isolated` on
coder-1 live only there.

Outside Git: applied (5 added, 3 changed) and coder-1 rebooted.

## Still to do

- **Merge `chore/agentgateway-scale-to-zero`.** Then check that
  `kubectl -n agentgateway get deploy agentgateway-proxy` shows `0/0`. The
  controller's handling of `replicas: 0` hasn't been tested.
- **Until the hardware changes, nothing serves 192.168.6.202.** The HTTPS
  allow rule is harmless meanwhile. On the new host, remove `replicas` from
  `apps/agentgateway/parameters-proxy.yaml`.
- **Set adguard-1 to stopped or remove it in `terraform.tfvars`,** so an
  untargeted apply doesn't start it.
- **Decide on inbound rules,** for example SSH only from the LAN and the
  Tailscale subnet router.
