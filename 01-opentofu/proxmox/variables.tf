variable "proxmox_endpoint" {
  description = "Proxmox API endpoint (e.g. https://192.168.1.10:8006/)"
  type        = string
}

variable "proxmox_username" {
  description = "Proxmox API username (e.g. root@pam or tofu@pve)"
  type        = string
  default     = "tofu@pve"
}

variable "proxmox_api_token" {
  description = "Proxmox API token (format: user@realm!tokenid=secret)"
  type        = string
  sensitive   = true
  default     = null
}

variable "node_name" {
  description = "Proxmox node to create the template on"
  type        = string
  default     = "pve"
}

variable "template_vm_id" {
  description = "VM ID for the Ubuntu template"
  type        = number
  default     = 9000
}

variable "template_name" {
  description = "Name for the Ubuntu cloud-init template"
  type        = string
  default     = "ubuntu-24.04-cloud"
}

variable "disk_storage" {
  description = "Storage pool for VM disks (check: pvesm status)"
  type        = string
  default     = "local-lvm"
}

variable "snippets_storage" {
  description = "Storage pool with snippets content type enabled"
  type        = string
  default     = "local"
}

variable "disk_size" {
  description = "Template disk size in GB"
  type        = number
  default     = 20
}

variable "vm_cores" {
  description = "Number of CPU cores for the template"
  type        = number
  default     = 2
}

variable "vm_memory" {
  description = "Memory in MB for the template"
  type        = number
  default     = 2048
}

variable "bridge" {
  description = "Network bridge to attach the template NIC to"
  type        = string
  default     = "vmbr0"
}

variable "ssh_public_key" {
  description = "SSH public key to inject into the template (contents, not file path)"
  type        = string
}

variable "cloud_init_file" {
  description = "Cloud-init user-data template filename, relative to the cloud-init/ directory"
  type        = string
}

variable "debian_template_vm_id" {
  description = "VM ID for the Debian 13 template"
  type        = number
  default     = 9001
}

variable "debian_template_name" {
  description = "Name for the Debian 13 cloud-init template"
  type        = string
  default     = "debian-13-cloud-init"
}

variable "debian_template_disk_size" {
  description = "Debian template disk size in GB. Keep it small: clones can't be smaller than this."
  type        = number
  default     = 20
}

variable "debian_cloud_init_file" {
  description = "Cloud-init user-data template for Debian VMs, relative to the cloud-init/ directory"
  type        = string
  default     = "debian-13-cloud-init.yaml"
}

variable "timezone" {
  description = "Timezone for the VM (e.g. America/New_York)"
  type        = string
  default     = "America/Chicago"
}

# ---------------------------------------------------------------------------
# Optional: VMs to clone from the template
# Software configuration (k3s, etc.) is Ansible's job — this only provisions.
# ansible_groups feeds the `inventory` output.
# ---------------------------------------------------------------------------
variable "vms" {
  description = "Map of VMs to clone from the template. Set to {} to skip."
  type = map(object({
    vm_id          = number
    cores          = optional(number, 2)
    max_memory     = optional(number, 2048) # MiB, Proxmox "dedicated"
    min_memory     = optional(number, 0)    # MiB, balloon floor ("floating"); 0 = ballooning off
    disk_gb        = optional(number, 40)
    tags           = optional(list(string), ["tofu-generated"])
    description    = optional(string, "")
    ansible_groups = optional(list(string), [])
    full_clone     = optional(bool, false)
    virtiofs       = optional(list(string), [])
    ip_address     = optional(string)           # CIDR, e.g. "192.168.4.50/22"; unset = DHCP
    template       = optional(string, "ubuntu") # "ubuntu" or "debian"
    dns_servers    = optional(list(string), []) # unset = the Proxmox host's resolvers
    # Proxmox firewall for VMs that run untrusted code (agents): no outbound
    # connections to private ranges (the LAN, the cluster, Tailscale) except
    # lan_isolated_allow. Incoming traffic isn't filtered. See firewall.tf.
    # Needs a static ip_address.
    lan_isolated = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for vm in values(var.vms) : contains(["ubuntu", "debian"], vm.template)])
    error_message = "vms[*].template must be \"ubuntu\" or \"debian\"."
  }

  validation {
    condition     = alltrue([for vm in values(var.vms) : !vm.lan_isolated || vm.ip_address != null])
    error_message = "vms[*].lan_isolated needs a static ip_address (the firewall's IP filter pins it)."
  }

  validation {
    condition     = alltrue([for vm in values(var.vms) : vm.vm_id >= 1000])
    error_message = "vms[*].vm_id must be 1000 or higher (100-999 is reserved for LXCs)."
  }
}

variable "lan_isolated_allow" {
  description = <<-EOT
    The only private destinations lan_isolated VMs may connect to, in order.
    The cluster is reachable only through agentgateway: not Traefik (*.lan
    services), node IPs, Service IPs or other MetalLB IPs.
    Each entry is a Proxmox macro (e.g. "DNS", "HTTPS") or proto + dport.
  EOT
  type = list(object({
    dest    = string
    macro   = optional(string)
    proto   = optional(string)
    dport   = optional(string)
    comment = string
  }))
  default = [
    { dest = "192.168.6.201", macro = "DNS", comment = "AdGuard Home (k3s, MetalLB): DNS only" },
    { dest = "192.168.6.202", macro = "HTTPS", comment = "agentgateway (agentgateway.lan)" },
  ]
}

variable "vm_gateway" {
  description = "Default gateway for VM static IPs"
  type        = string
  default     = "192.168.4.1"
}

# ---------------------------------------------------------------------------
# Optional: LXC containers
# ---------------------------------------------------------------------------
variable "lxc_gateway" {
  description = "Default gateway for LXC static IPs"
  type        = string
  default     = "192.168.4.1"
}

variable "lxc_template_storage" {
  description = "Storage pool with the vztmpl (container templates) content type enabled"
  type        = string
  default     = "local"
}

variable "lxc_template_url" {
  description = "Container template to download (see `pveam available`)"
  type        = string
  default     = "https://download.proxmox.com/images/system/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "lxc_template_file_name" {
  description = "File name for the downloaded container template"
  type        = string
  default     = "ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "lxcs" {
  description = "Map of LXC containers to create. Set to {} to skip."
  type = map(object({
    vm_id = number
    # Static address in CIDR form, e.g. "192.168.5.110/24"
    ip_address     = string
    cores          = optional(number, 1)
    memory         = optional(number, 512)
    swap           = optional(number, 512)
    disk_gb        = optional(number, 8)
    privileged     = optional(bool, false)
    nesting        = optional(bool, false)
    start_on_boot  = optional(bool, true)
    tags           = optional(list(string), ["tofu-generated"])
    description    = optional(string, "")
    ansible_groups = optional(list(string), [])
    # Host device nodes to pass through, e.g. ["/dev/net/tun"] for Tailscale.
    # Like bind mounts, Proxmox only allows this when authenticated as root@pam.
    devices = optional(list(string), [])
    # Bind mounts of host directories into the container. The host path must
    # already exist. Proxmox only allows this when authenticated as root@pam
    # (not an API token).
    mount_points = optional(list(object({
      host_path      = string
      container_path = string
      read_only      = optional(bool, false)
    })), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for ct in values(var.lxcs) : ct.vm_id >= 100 && ct.vm_id <= 999])
    error_message = "lxcs[*].vm_id must be between 100 and 999 (1000+ is reserved for VMs)."
  }
}

variable "dir_mappings" {
  description = "Host directories exposed as Proxmox directory mappings (for virtiofs). Map of mapping name => host path."
  type        = map(string)
  default     = {}
}
