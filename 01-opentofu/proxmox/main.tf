terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Provider
# Use an API token instead of password where possible — create one at:
# Datacenter > Permissions > API Tokens
# ---------------------------------------------------------------------------
provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  username  = var.proxmox_username
  api_token = var.proxmox_api_token

  # Accept self-signed TLS cert (common for homelab Proxmox installs)
  insecure = true

  ssh {
    agent    = true
    username = "root"
  }
}

# ---------------------------------------------------------------------------
# 1. Download Ubuntu 24.04 cloud image to Proxmox
# ---------------------------------------------------------------------------
resource "proxmox_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = var.snippets_storage
  node_name    = var.node_name

  # url       = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name = "noble-server-cloudimg-amd64.img"

  # Optional: pin to a specific release and set checksum for reproducibility
  url                = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  checksum           = "04e8f2461a16a44e78a370284471f29616cdd9baf1893df25807b71f985b6c94"
  checksum_algorithm = "sha256"
}

# ---------------------------------------------------------------------------
# 2. Upload cloud-init user-data snippets
# Cloud-init only handles OS bootstrap (users, packages, SSH hardening) —
# everything else is Ansible's job, run after the VM exists.
# ---------------------------------------------------------------------------
resource "proxmox_virtual_environment_file" "template_cloud_init" {
  content_type = "snippets"
  datastore_id = var.snippets_storage
  node_name    = var.node_name

  source_raw {
    data = templatefile("${path.module}/cloud-init/${var.cloud_init_file}", {
      hostname       = var.template_name
      timezone       = var.timezone
      ssh_public_key = trimspace(var.ssh_public_key)
    })
    file_name = "template-userdata.yaml"
  }
}

# One rendered snippet per cloned VM — each needs its own hostname baked in.
resource "proxmox_virtual_environment_file" "cloud_init_user_data" {
  for_each = var.vms

  content_type = "snippets"
  datastore_id = var.snippets_storage
  node_name    = var.node_name

  source_raw {
    data = templatefile("${path.module}/cloud-init/${var.cloud_init_file}", {
      hostname       = each.key
      timezone       = var.timezone
      ssh_public_key = trimspace(var.ssh_public_key)
    })
    file_name = "${each.key}-userdata.yaml"
  }
}

# ---------------------------------------------------------------------------
# 3. Ubuntu 24.04 cloud-init template VM
# ---------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "ubuntu_template" {
  name      = var.template_name
  node_name = var.node_name
  vm_id     = var.template_vm_id
  template  = true

  description = "Ubuntu 24.04 LTS (Noble) cloud-init template — managed by OpenTofu"
  tags        = ["ubuntu", "cloud-init", "template"]

  agent {
    enabled = true
  }

  cpu {
    cores = var.vm_cores
    type  = "host"
  }

  memory {
    dedicated = var.vm_memory
    floating  = 512 # MiB
  }

  # Boot disk — imported from the cloud image
  disk {
    datastore_id = var.disk_storage
    file_id      = proxmox_download_file.ubuntu_cloud_image.id
    interface    = "scsi0"
    size         = var.disk_size
    discard      = "on"
    ssd          = true
    file_format  = "raw"
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  # Required for cloud images to display output
  serial_device {}
  vga {
    type = "serial0"
  }

  # SCSI controller
  scsi_hardware = "virtio-scsi-pci"

  # Boot order
  boot_order = ["scsi0"]

  # cloud-init
  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    # user_data_file_id = cicustom user= in Proxmox; uploads snippet to storage and mounts it on the cloud-init CD-ROM instead of the generated user-data
    # replaces Proxmox's generated user-data entirely — SSH keys must live in the snippet itself, not in user_account
    user_data_file_id = proxmox_virtual_environment_file.template_cloud_init.id
  }

  lifecycle {
    prevent_destroy = false
    # Template disks become read-only base volumes (base-VMID-disk-N) after
    # conversion — Proxmox rejects resize attempts on them. Clones get their
    # own disk, so template disk size drift is harmless to ignore.
    ignore_changes = [disk]
  }
}

# Directory mappings let VMs mount host paths (e.g. ZFS datasets) via virtiofs
resource "proxmox_hardware_mapping_dir" "dir" {
  for_each = var.dir_mappings

  name = each.key
  map = [{
    node = var.node_name
    path = each.value
  }]
}

# ---------------------------------------------------------------------------
# 4. (Optional) Clone VMs from the template
# Populate var.vms to create VMs, e.g.:
#   vms = {
#     "server-1" = { vm_id = 1001, ansible_groups = ["k3s_server"] }
#     "agent-1"  = { vm_id = 1002, max_memory = 4096, ansible_groups = ["k3s_agent"] }
#   }
# ansible_groups drives the `inventory` output used by Ansible.
# ---------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vms

  name        = each.key
  node_name   = var.node_name
  vm_id       = each.value.vm_id
  tags        = each.value.tags
  description = each.value.description

  clone {
    vm_id = proxmox_virtual_environment_vm.ubuntu_template.vm_id
    full  = each.value.full_clone
  }

  # Required so Terraform waits for and reports the guest-agent-assigned
  # IP address in ipv4_addresses — without this, vm_ips stays "pending".
  agent {
    enabled = true
  }

  # Let cores/memory be bumped later via tofu apply without a stop/start.
  # numa is required by Proxmox for memory hotplug specifically.
  # Proxmox refuses to start a VM with memory hotplug + virtio-fs, so drop it there.
  hotplug = length(each.value.virtiofs) > 0 ? "network,disk,usb,cpu" : "network,disk,usb,cpu,memory"

  cpu {
    cores = each.value.cores
    type  = "host"
    numa  = true
  }

  memory {
    dedicated = each.value.max_memory
    floating  = each.value.min_memory
  }

  disk {
    datastore_id = var.disk_storage
    interface    = "scsi0"
    size         = each.value.disk_gb
    discard      = "on"
    ssd          = true
  }

  # Reference the mapping resource (not the bare name) so it's created first
  dynamic "virtiofs" {
    for_each = each.value.virtiofs
    content {
      mapping   = proxmox_hardware_mapping_dir.dir[virtiofs.value].name
      cache     = "always"
      direct_io = true
    }
  }

  initialization {
    ip_config {
      ipv4 {
        address = coalesce(each.value.ip_address, "dhcp")
        gateway = each.value.ip_address != null ? var.vm_gateway : null
      }
    }

    # user_data_file_id = cicustom user= in Proxmox; uploads snippet to storage and mounts it on the cloud-init CD-ROM instead of the generated user-data
    # replaces Proxmox's generated user-data entirely — SSH keys must live in the snippet itself, not in user_account
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data[each.key].id
  }

  # Start VM after creation
  started = true
}

# ---------------------------------------------------------------------------
# 5. (Optional) LXC containers
# Populate var.lxcs to create containers, e.g.:
#   lxcs = {
#     "dns-1" = { vm_id = 101, ansible_groups = ["dns"] }
#   }
# ---------------------------------------------------------------------------
# Use the template if it's already on the storage pool; download it otherwise.
data "proxmox_files" "lxc_template" {
  node_name       = var.node_name
  datastore_id    = var.lxc_template_storage
  content_type    = "vztmpl"
  file_name_regex = "^${var.lxc_template_file_name}$"
}

locals {
  lxc_template_present = anytrue([
    for f in data.proxmox_files.lxc_template.files : f.file_name == var.lxc_template_file_name
  ])
  lxc_template_file_id = "${var.lxc_template_storage}:vztmpl/${var.lxc_template_file_name}"
}

resource "proxmox_download_file" "lxc_template" {
  count = length(var.lxcs) > 0 && !local.lxc_template_present ? 1 : 0

  content_type = "vztmpl"
  datastore_id = var.lxc_template_storage
  node_name    = var.node_name
  url          = var.lxc_template_url
  file_name    = var.lxc_template_file_name
}

resource "proxmox_virtual_environment_container" "lxc" {
  for_each = var.lxcs

  node_name     = var.node_name
  vm_id         = each.value.vm_id
  tags          = each.value.tags
  description   = each.value.description
  unprivileged  = !each.value.privileged
  start_on_boot = each.value.start_on_boot
  started       = true

  operating_system {
    template_file_id = local.lxc_template_present ? local.lxc_template_file_id : try(proxmox_download_file.lxc_template[0].id, null)
    type             = "ubuntu"
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
    swap      = each.value.swap
  }

  disk {
    datastore_id = var.disk_storage
    size         = each.value.disk_gb
  }

  network_interface {
    name   = "eth0"
    bridge = var.bridge
  }

  dynamic "mount_point" {
    for_each = each.value.mount_points
    content {
      volume    = mount_point.value.host_path
      path      = mount_point.value.container_path
      read_only = mount_point.value.read_only
    }
  }

  dynamic "device_passthrough" {
    for_each = toset(each.value.devices)
    content {
      path = device_passthrough.value
    }
  }

  features {
    nesting = each.value.nesting
  }

  initialization {
    hostname = each.key

    ip_config {
      ipv4 {
        address = each.value.ip_address
        gateway = var.lxc_gateway
      }
    }

    user_account {
      keys = [trimspace(var.ssh_public_key)]
    }
  }
}
