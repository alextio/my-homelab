output "template_vm_id" {
  description = "VM ID of the Ubuntu cloud-init template"
  value       = proxmox_virtual_environment_vm.ubuntu_template.vm_id
}

output "template_name" {
  description = "Name of the Ubuntu cloud-init template"
  value       = proxmox_virtual_environment_vm.ubuntu_template.name
}

output "cloud_image_id" {
  description = "Proxmox file ID of the downloaded Ubuntu cloud image"
  value       = proxmox_download_file.ubuntu_cloud_image.id
}

output "debian_template_vm_id" {
  description = "VM ID of the Debian 13 cloud-init template"
  value       = proxmox_virtual_environment_vm.debian_template.vm_id
}

output "debian_cloud_image_id" {
  description = "Proxmox file ID of the downloaded Debian 13 cloud image"
  value       = proxmox_download_file.debian_cloud_image.id
}

output "vm_ips" {
  description = "IP addresses of cloned VMs (populated once VMs are running)"
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm :
    name => try(vm.ipv4_addresses[1][0], "pending")
  }
}

output "lxc_ips" {
  description = "IP addresses of LXC containers (populated once running)"
  value = {
    for name, ct in proxmox_virtual_environment_container.lxc :
    name => try(ct.ipv4["eth0"], "pending")
  }
}

output "inventory" {
  description = "Host name -> {ip, type, groups}, for the Ansible dynamic inventory"
  value = merge(
    {
      for name, vm in proxmox_virtual_environment_vm.vm :
      name => {
        ip     = try(vm.ipv4_addresses[1][0], "pending")
        type   = "vm"
        groups = var.vms[name].ansible_groups
      }
    },
    {
      for name, ct in proxmox_virtual_environment_container.lxc :
      name => {
        ip     = try(ct.ipv4["eth0"], "pending")
        type   = "lxc"
        groups = var.lxcs[name].ansible_groups
      }
    }
  )
}
