# ---------------------------------------------------------------------------
# Connection
# ---------------------------------------------------------------------------
variable "incus_remote_name" {
  description = "Name for the Incus remote (local alias only)"
  type        = string
  default     = "homelab"
}

variable "incus_address" {
  description = "Incus API endpoint, e.g. https://192.168.4.111:8443"
  type        = string
}

variable "incus_trust_token" {
  description = "One-time trust token from `incus config trust add` (plain Incus only; IncusOS trusts the cert from its install seed). Unset once trusted."
  type        = string
  sensitive   = true
  default     = null
}

# ---------------------------------------------------------------------------
# Host resources
# ---------------------------------------------------------------------------
variable "storage_pool" {
  description = "Incus storage pool for root disks and volumes (IncusOS: \"local\"; plain Incus: usually \"default\"). Check: incus storage list"
  type        = string
  default     = "local"
}

variable "bridge" {
  description = "Host bridge on the LAN that instance NICs attach to (nictype=bridged). Check: incus network list"
  type        = string
}

variable "gateway" {
  description = "Default gateway for static IPs"
  type        = string
  default     = "192.168.4.1"
}

variable "dns_servers" {
  description = "DNS servers for static IPs"
  type        = list(string)
  default     = ["192.168.4.1"]
}

# ---------------------------------------------------------------------------
# Cloud-init
# ---------------------------------------------------------------------------
variable "ssh_public_key" {
  description = "SSH public key injected via cloud-init (contents, not file path)"
  type        = string
}

variable "timezone" {
  description = "Timezone for instances (e.g. America/New_York)"
  type        = string
  default     = "America/Chicago"
}

variable "cloud_init_file" {
  description = "Cloud-init user-data template for Ubuntu instances, relative to cloud-init/"
  type        = string
  default     = "ubuntu-24.04-cloud-init.yaml"
}

variable "debian_cloud_init_file" {
  description = "Cloud-init user-data template for Debian instances, relative to cloud-init/"
  type        = string
  default     = "debian-13-cloud-init.yaml"
}

variable "alma_cloud_init_file" {
  description = "Cloud-init user-data template for AlmaLinux instances, relative to cloud-init/"
  type        = string
  default     = "almalinux-10-cloud-init.yaml"
}

# ---------------------------------------------------------------------------
# Shared storage
# ---------------------------------------------------------------------------
variable "storage_volumes" {
  description = "Custom filesystem volumes to create in storage_pool. Map of name => size in GiB. Attach with vms/lxcs[*].volumes."
  type        = map(number)
  default     = {}
}

# ---------------------------------------------------------------------------
# Instances
# Incus identifies instances by name, so there is no vm_id.
# ---------------------------------------------------------------------------
variable "vms" {
  description = "Map of VMs to create. Set to {} to skip."
  type = map(object({
    os             = optional(string, "ubuntu") # "ubuntu", "debian" or "alma"
    cores          = optional(number, 2)
    memory         = optional(number, 2048) # MiB
    disk_gb        = optional(number, 40)
    ip_address     = optional(string) # CIDR, e.g. "192.168.4.50/22"; unset = DHCP
    start_on_boot  = optional(bool, true)
    tags           = optional(list(string), ["tofu-generated"])
    description    = optional(string, "")
    ansible_groups = optional(list(string), [])
    volumes = optional(list(object({
      name      = string # key in storage_volumes
      path      = string # mount point in the guest
      read_only = optional(bool, false)
    })), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for vm in values(var.vms) : contains(["ubuntu", "debian", "alma"], vm.os)])
    error_message = "vms[*].os must be \"ubuntu\", \"debian\" or \"alma\"."
  }
}

variable "lxcs" {
  description = "Map of system containers to create. Set to {} to skip."
  type = map(object({
    os             = optional(string, "ubuntu") # "ubuntu", "debian" or "alma"
    ip_address     = optional(string)           # CIDR; unset = DHCP
    cores          = optional(number, 1)
    memory         = optional(number, 512) # MiB
    disk_gb        = optional(number, 8)
    privileged     = optional(bool, false)
    nesting        = optional(bool, false)
    start_on_boot  = optional(bool, true)
    tags           = optional(list(string), ["tofu-generated"])
    description    = optional(string, "")
    ansible_groups = optional(list(string), [])
    # Host device nodes to pass through, e.g. ["/dev/net/tun"] for Tailscale.
    devices = optional(list(string), [])
    volumes = optional(list(object({
      name      = string
      path      = string
      read_only = optional(bool, false)
    })), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for ct in values(var.lxcs) : contains(["ubuntu", "debian", "alma"], ct.os)])
    error_message = "lxcs[*].os must be \"ubuntu\", \"debian\" or \"alma\"."
  }
}
