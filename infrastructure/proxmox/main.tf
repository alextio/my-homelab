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
  url                = "https://cloud-images.ubuntu.com/noble/20260705/noble-server-cloudimg-amd64.img"
  checksum           = "ffe6203da54deeb6db5d2a98a83f9ec8e55f149d3f7ba622e1abe5fa966ee3d6"
  checksum_algorithm = "sha256"
}

# ---------------------------------------------------------------------------
# 2. Upload cloud-init user-data snippet
# ---------------------------------------------------------------------------
resource "proxmox_virtual_environment_file" "cloud_init_user_data" {
  content_type = "snippets"
  datastore_id = var.snippets_storage
  node_name    = var.node_name

  source_raw {
    # Render the user-data template with the configured timezone
    data = templatefile("${path.module}/cloud-init/proxmox-ubuntu.yaml", {
      timezone       = var.timezone
      user           = var.default_user
      ssh_public_key = trimspace(var.ssh_public_key)
    })
    file_name = "ubuntu-24.04-userdata.yaml"
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
    floating = 512 # MiB
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
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data.id
  }

  lifecycle {
    prevent_destroy = false
    # Template disks become read-only base volumes (base-VMID-disk-N) after
    # conversion — Proxmox rejects resize attempts on them. Clones get their
    # own disk, so template disk size drift is harmless to ignore.
    ignore_changes = [disk]
  }
}

# ---------------------------------------------------------------------------
# 4. (Optional) Clone VMs from the template
# Populate var.vms to create VMs, e.g.:
#   vms = {
#     "k3s-node-1" = { vm_id = 10001 }
#     "k3s-node-2" = { vm_id = 10002, memory = 4096 }
#   }
# ---------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vms

  name      = each.key
  node_name = var.node_name
  vm_id     = each.value.vm_id
  tags      = each.value.tags

  clone {
    vm_id = proxmox_virtual_environment_vm.ubuntu_template.vm_id
    full  = true
  }

  # Required so Terraform waits for and reports the guest-agent-assigned
  # IP address in ipv4_addresses — without this, vm_ips stays "pending"
  # and the k3s bootstrap provisioner below has nothing to connect to.
  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.disk_storage
    interface    = "scsi0"
    size         = each.value.disk_gb
    discard      = "on"
    ssd          = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    # user_data_file_id = cicustom user= in Proxmox; uploads snippet to storage and mounts it on the cloud-init CD-ROM instead of the generated user-data
    # replaces Proxmox's generated user-data entirely — SSH keys must live in the snippet itself, not in user_account
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data.id
  }

  # Start VM after creation
  started = true
}

# ---------------------------------------------------------------------------
# 5. Bootstrap k3s on each cloned VM via k3sup, right after it comes up
# ---------------------------------------------------------------------------
resource "terraform_data" "k3s_bootstrap" {
  for_each = var.vms

  # Re-run if the VM is recreated or its IP changes
  triggers_replace = [
    proxmox_virtual_environment_vm.vm[each.key].vm_id,
    proxmox_virtual_environment_vm.vm[each.key].ipv4_addresses,
  ]

  provisioner "local-exec" {
    command     = "${path.module}/../../scripts/k3sup-bootstrap.sh ${each.key}"
    working_dir = path.module

    environment = {
      K3S_SSH_USER = var.default_user
      K3S_NODE_IP  = proxmox_virtual_environment_vm.vm[each.key].ipv4_addresses[1][0]
    }
  }
}
