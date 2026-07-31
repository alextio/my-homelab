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

variable "default_user" {
  description = "Default cloud-init user"
  type        = string
  default     = "ubuntu"
}

variable "timezone" {
  description = "Timezone for the VM (e.g. America/New_York)"
  type        = string
  default     = "America/Chicago"
}

# ---------------------------------------------------------------------------
# Optional: VM clones to create from the template
# ---------------------------------------------------------------------------
variable "vms" {
  description = "Map of VMs to clone from the template. Set to {} to skip."
  type = map(object({
    vm_id   = number
    cores   = optional(number, 2)
    memory  = optional(number, 2048)
    disk_gb = optional(number, 40)
    tags    = optional(list(string), ["tofu-generated"])
  }))
  default = {}
}
