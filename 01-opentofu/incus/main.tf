terraform {
  required_version = ">= 1.6.0"

  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 1.2.1"
    }
  }
}

# ---------------------------------------------------------------------------
# Provider
# Everything goes through the Incus API with a TLS client certificate — no SSH.
# The client cert lives in config_dir (default ~/.config/incus). On IncusOS it
# must be the certificate you baked into the install seed; on plain Incus you
# can trust it once with a token from `incus config trust add <name>`.
# ---------------------------------------------------------------------------
provider "incus" {
  accept_remote_certificate    = true # self-signed server cert (homelab)
  generate_client_certificates = true
  default_remote               = var.incus_remote_name

  remote {
    name    = var.incus_remote_name
    address = var.incus_address
    token   = var.incus_trust_token
  }

  # Public image server; declared explicitly so it doesn't depend on a local
  # incus CLI config existing.
  remote {
    name     = "images"
    address  = "https://images.linuxcontainers.org"
    protocol = "simplestreams"
    public   = true
  }
}

# ---------------------------------------------------------------------------
# 1. Images
# The /cloud variants ship with cloud-init (and incus-agent for VMs), so they
# replace both the downloaded qcow2 and the Proxmox template VM. Incus stores
# them in the writable storage pool — the read-only IncusOS root never matters.
# ---------------------------------------------------------------------------
locals {
  os_images = {
    ubuntu = {
      image           = "ubuntu/24.04/cloud"
      cloud_init_file = var.cloud_init_file
    }
    debian = {
      image           = "debian/13/cloud"
      cloud_init_file = var.debian_cloud_init_file
    }
    # Needs an x86-64-v3 host (Haswell or newer)
    alma = {
      image           = "almalinux/10/cloud"
      cloud_init_file = var.alma_cloud_init_file
    }
  }

  # Only pull the (OS, type) pairs something actually uses.
  vm_oses  = toset([for vm in values(var.vms) : vm.os])
  lxc_oses = toset([for ct in values(var.lxcs) : ct.os])
}

resource "incus_image" "vm" {
  for_each = local.vm_oses

  source_image = {
    remote = "images"
    name   = local.os_images[each.key].image
    type   = "virtual-machine"
  }
}

resource "incus_image" "container" {
  for_each = local.lxc_oses

  source_image = {
    remote = "images"
    name   = local.os_images[each.key].image
    type   = "container"
  }
}

# ---------------------------------------------------------------------------
# 2. Shared storage volumes (replaces Proxmox dir mappings / bind mounts)
# Custom filesystem volumes can be attached to VMs (shared via virtiofs
# automatically) and containers alike.
# ---------------------------------------------------------------------------
resource "incus_storage_volume" "vol" {
  for_each = var.storage_volumes

  name         = each.key
  pool         = var.storage_pool
  content_type = "filesystem"
  config = {
    size = "${each.value}GiB"
  }
}

# ---------------------------------------------------------------------------
# 3. Cloud-init
# Rendered straight into instance config keys — no snippet upload step.
# Cloud-init only handles OS bootstrap; everything else is Ansible's job.
# ---------------------------------------------------------------------------
locals {
  instances = merge(
    { for name, vm in var.vms : name => merge(vm, { kind = "vm" }) },
    { for name, ct in var.lxcs : name => merge(ct, { kind = "lxc" }) },
  )

  user_data = {
    for name, inst in local.instances : name => templatefile(
      "${path.module}/cloud-init/${local.os_images[inst.os].cloud_init_file}",
      {
        hostname       = name
        timezone       = var.timezone
        ssh_public_key = trimspace(var.ssh_public_key)
      }
    )
  }

  network_config = {
    for name, inst in local.instances : name => templatefile(
      "${path.module}/cloud-init/network-config.yaml.tftpl",
      {
        ip_address  = inst.ip_address
        gateway     = var.gateway
        dns_servers = var.dns_servers
      }
    )
  }
}

# ---------------------------------------------------------------------------
# 4. VMs
#   vms = {
#     "server-1" = { ansible_groups = ["k3s_server"] }
#     "podman-1" = { os = "debian" }
#   }
# ---------------------------------------------------------------------------
resource "incus_instance" "vm" {
  for_each = var.vms

  name        = each.key
  type        = "virtual-machine"
  image       = incus_image.vm[each.value.os].fingerprint
  description = each.value.description
  running     = true

  config = {
    "limits.cpu"                = tostring(each.value.cores)
    "limits.memory"             = "${each.value.memory}MiB"
    "boot.autostart"            = tostring(each.value.start_on_boot)
    "user.tags"                 = join(",", each.value.tags)
    "cloud-init.user-data"      = local.user_data[each.key]
    "cloud-init.network-config" = local.network_config[each.key]
  }

  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = var.storage_pool
      size = "${each.value.disk_gb}GiB"
    }
  }

  device {
    name = "eth0"
    type = "nic"
    properties = {
      nictype = "bridged"
      parent  = var.bridge
    }
  }

  dynamic "device" {
    for_each = { for v in each.value.volumes : v.name => v }
    content {
      name = "vol-${device.key}"
      type = "disk"
      properties = {
        pool     = var.storage_pool
        source   = incus_storage_volume.vol[device.key].name
        path     = device.value.path
        readonly = tostring(device.value.read_only)
      }
    }
  }

  # Wait for incus-agent to report an address so vm_ips/inventory are filled.
  wait_for {
    type = "ipv4"
  }
}

# ---------------------------------------------------------------------------
# 5. Containers
#   lxcs = {
#     "dns-1" = { ip_address = "192.168.5.101/22", ansible_groups = ["dns"] }
#   }
# ---------------------------------------------------------------------------
resource "incus_instance" "lxc" {
  for_each = var.lxcs

  name        = each.key
  type        = "container"
  image       = incus_image.container[each.value.os].fingerprint
  description = each.value.description
  running     = true

  config = {
    "limits.cpu"                = tostring(each.value.cores)
    "limits.memory"             = "${each.value.memory}MiB"
    "boot.autostart"            = tostring(each.value.start_on_boot)
    "security.privileged"       = tostring(each.value.privileged)
    "security.nesting"          = tostring(each.value.nesting)
    "user.tags"                 = join(",", each.value.tags)
    "cloud-init.user-data"      = local.user_data[each.key]
    "cloud-init.network-config" = local.network_config[each.key]
  }

  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = var.storage_pool
      size = "${each.value.disk_gb}GiB"
    }
  }

  device {
    name = "eth0"
    type = "nic"
    properties = {
      nictype = "bridged"
      parent  = var.bridge
    }
  }

  dynamic "device" {
    for_each = { for v in each.value.volumes : v.name => v }
    content {
      name = "vol-${device.key}"
      type = "disk"
      properties = {
        pool     = var.storage_pool
        source   = incus_storage_volume.vol[device.key].name
        path     = device.value.path
        readonly = tostring(device.value.read_only)
      }
    }
  }

  # Host device nodes, e.g. /dev/net/tun for Tailscale.
  dynamic "device" {
    for_each = { for i, path in each.value.devices : "dev${i}" => path }
    content {
      name = device.key
      type = "unix-char"
      properties = {
        source = device.value
        path   = device.value
      }
    }
  }

  wait_for {
    type = "ipv4"
  }
}
