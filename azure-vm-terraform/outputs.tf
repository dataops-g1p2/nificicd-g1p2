output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.rg.name
}

output "vm_public_ip" {
  description = "Public IP address of the VM"
  value       = azurerm_public_ip.pip.ip_address
}

output "vm_name" {
  description = "Virtual machine name"
  value       = azurerm_linux_virtual_machine.vm.name
}

output "admin_username" {
  description = "Admin username"
  value       = var.admin_username
}

output "nifi_url" {
  description = "NiFi web interface URL"
  value       = "https://${azurerm_public_ip.pip.ip_address}:8443/nifi"
}

output "registry_url" {
  description = "NiFi Registry URL"
  value       = "http://${azurerm_public_ip.pip.ip_address}:18080/nifi-registry"
}

output "ssh_command" {
  description = "SSH command to connect to VM"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.pip.ip_address}"
}