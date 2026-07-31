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

output "vm_ips" {
  description = "IP addresses of cloned VMs (populated once VMs are running)"
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm :
    name => try(vm.ipv4_addresses[1][0], "pending")
  }
}
