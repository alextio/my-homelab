output "image_fingerprints" {
  description = "Fingerprints of the cached images, keyed by \"<os>-<vm|container>\""
  value = merge(
    { for os, img in incus_image.vm : "${os}-vm" => img.fingerprint },
    { for os, img in incus_image.container : "${os}-container" => img.fingerprint },
  )
}

output "vm_ips" {
  description = "IPv4 addresses of VMs (reported by incus-agent)"
  value = {
    for name, vm in incus_instance.vm :
    name => coalesce(vm.ipv4_address, "pending")
  }
}

output "lxc_ips" {
  description = "IPv4 addresses of containers"
  value = {
    for name, ct in incus_instance.lxc :
    name => coalesce(ct.ipv4_address, "pending")
  }
}

# Same shape as the proxmox module's output, so the Ansible inventory works
# unchanged against either backend.
output "inventory" {
  description = "Host name -> {ip, type, groups}, for the Ansible dynamic inventory"
  value = merge(
    {
      for name, vm in incus_instance.vm :
      name => {
        ip     = coalesce(vm.ipv4_address, "pending")
        type   = "vm"
        groups = var.vms[name].ansible_groups
      }
    },
    {
      for name, ct in incus_instance.lxc :
      name => {
        ip     = coalesce(ct.ipv4_address, "pending")
        type   = "lxc"
        groups = var.lxcs[name].ansible_groups
      }
    }
  )
}
