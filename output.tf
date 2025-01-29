output "DC_ID" {
  description = "id of vSphere Datacenter"
  value       = data.vsphere_datacenter.dc.id
}

output "ResPool_ID" {
  description = "Resource Pool id"
  value       = data.vsphere_resource_pool.pool.id
}

output "VM" {
  description = "VM Names"
  value       = vsphere_virtual_machine.vm.*.name
}

output "ipold" {
  description = "default ip address of the deployed VM"
  value       = vsphere_virtual_machine.vm.*.default_ip_address
}

output "ip" {
  description = "static ip address of the deployed VM"
  #value       = vsphere_virtual_machine.vm.*.clone.0.customize.0.network_interface.0.ipv4_address 
  value       = vsphere_virtual_machine.vm.*.default_ip_address
}

output "guest-ip" {
  description = "all the registered ip address of the VM"
  value       = vsphere_virtual_machine.vm.*.guest_ip_addresses
}

output "uuid" {
  description = "UUID of the VM in vSphere"
  value       = vsphere_virtual_machine.vm.*.uuid
}

output "disk" {
  description = "Disks of the deployed VM"
  value       = vsphere_virtual_machine.vm.*.disk
}

output "tags" {
  description = "Disks of the deployed VM"
  value       = vsphere_virtual_machine.vm.*.tags
}
