variable "proxmox_endpoint" {
  description = "Proxmox API endpoint (e.g. https://192.168.1.10:8006/)"
  type        = string
}

variable "proxmox_username" {
  description = "Proxmox API username (e.g. root@pam or tofu@pve)"
  type        = string
  default     = "tofu@pve"
}

variable "proxmox_password" {
  description = "Proxmox API password"
  type        = string
  sensitive   = true
  default     = null
}

variable "proxmox_api_token" {
  description = "Proxmox API token (alternative to password, format: user@realm!tokenid=secret)"
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
    ip_address     = optional(string) # CIDR, e.g. "192.168.4.50/22"; unset = DHCP
  }))
  default = {}
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
    vm_id          = number
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
}

variable "dir_mappings" {
  description = "Host directories exposed as Proxmox directory mappings (for virtiofs). Map of mapping name => host path."
  type        = map(string)
  default     = {}
}
