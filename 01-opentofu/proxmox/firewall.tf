# ---------------------------------------------------------------------------
# Proxmox firewall for lan_isolated VMs (vms[*].lan_isolated)
#
# These VMs run coding agents with sudo, so the rules live on the Proxmox
# host, where nothing inside the VM can change them:
#   out: lan_isolated_allow (DNS, agentgateway), then nothing else
#        in a private range, then the internet. The cluster is reachable
#        only through agentgateway: not Traefik or any other address.
#   in:  not filtered for now (input policy ACCEPT).
# Replies to allowed connections pass automatically (conntrack).
#
# Not covered: traffic inside a Tailscale tunnel on the VM itself. The host
# only sees the encrypted packets, so the tailnet ACL decides what flows
# through it.
# ---------------------------------------------------------------------------

locals {
  lan_isolated_vms = { for name, vm in var.vms : name => vm if vm.lan_isolated }
}

# Datacenter switch: guest firewalls only run while it's on. ACCEPT for the
# host and every VM without its own firewall, so turning it on changes
# nothing for them. With Proxmox's default (input DROP) the host would only
# accept its own subnet, which can lock out the web UI and SSH from
# elsewhere.
resource "proxmox_virtual_environment_cluster_firewall" "datacenter" {
  count = length(local.lan_isolated_vms) > 0 ? 1 : 0

  enabled        = true
  input_policy   = "ACCEPT"
  output_policy  = "ACCEPT"
  forward_policy = "ACCEPT"
}

# Everything a lan_isolated VM may not connect to, IPv4 and IPv6.
resource "proxmox_virtual_environment_firewall_ipset" "private" {
  count = length(local.lan_isolated_vms) > 0 ? 1 : 0

  name    = "private"
  comment = "Managed by OpenTofu (firewall.tf): blocked for lan_isolated VMs"

  dynamic "cidr" {
    for_each = {
      "10.0.0.0/8"     = "RFC 1918"
      "172.16.0.0/12"  = "RFC 1918"
      "192.168.0.0/16" = "RFC 1918 (the LAN)"
      "100.64.0.0/10"  = "CGNAT (Tailscale)"
      "169.254.0.0/16" = "link-local"
      "224.0.0.0/4"    = "multicast (mDNS, SSDP)"
      "fc00::/7"       = "IPv6 ULA (the LAN's IPv6)"
      "ff00::/8"       = "IPv6 multicast"
    }
    content {
      name    = cidr.key
      comment = cidr.value
    }
  }
}

# With ipfilter on, the VM may only send from these addresses (plus its
# MAC's IPv6 link-local), so sudo can't switch it to another IP to get
# around the rules.
resource "proxmox_virtual_environment_firewall_ipset" "ipfilter" {
  for_each = local.lan_isolated_vms

  node_name = var.node_name
  vm_id     = proxmox_virtual_environment_vm.vm[each.key].vm_id
  name      = "ipfilter-net0"
  comment   = "Managed by OpenTofu (firewall.tf)"

  cidr {
    name = split("/", each.value.ip_address)[0]
  }
}

# First match wins, in this order.
resource "proxmox_virtual_environment_firewall_rules" "lan_isolated" {
  for_each = local.lan_isolated_vms

  node_name = var.node_name
  vm_id     = proxmox_virtual_environment_vm.vm[each.key].vm_id

  dynamic "rule" {
    for_each = var.lan_isolated_allow
    content {
      type    = "out"
      action  = "ACCEPT"
      dest    = rule.value.dest
      macro   = rule.value.macro
      proto   = rule.value.proto
      dport   = rule.value.dport
      comment = rule.value.comment
    }
  }

  rule {
    type    = "out"
    action  = "DROP"
    dest    = "+dc/${proxmox_virtual_environment_firewall_ipset.private[0].name}"
    comment = "Nothing else on the LAN, in the cluster or on Tailscale"
  }
}

# Turned on last, once the rules and IP sets exist, so the VM is never
# filtered by a half-built rule set.
resource "proxmox_virtual_environment_firewall_options" "lan_isolated" {
  for_each = local.lan_isolated_vms

  node_name = var.node_name
  vm_id     = proxmox_virtual_environment_vm.vm[each.key].vm_id

  enabled = true
  # Incoming traffic isn't filtered for now.
  input_policy  = "ACCEPT"
  output_policy = "ACCEPT"
  ipfilter      = true
  macfilter     = true
  ndp           = true
  radv          = false
  dhcp          = false

  depends_on = [
    proxmox_virtual_environment_cluster_firewall.datacenter,
    proxmox_virtual_environment_firewall_ipset.ipfilter,
    proxmox_virtual_environment_firewall_rules.lan_isolated,
  ]
}
