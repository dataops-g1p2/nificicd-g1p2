output "vm_public_ip" {
  value       = azurerm_public_ip.public_ip.ip_address
  description = "The public IP address of the VM"
  sensitive   = true  
}

output "public_ip" {
  value     = azurerm_linux_virtual_machine.vm.public_ip_address
  sensitive = true  
}

output "ssh_cmd" {
  value     = "ssh ${azurerm_linux_virtual_machine.vm.admin_username}@${azurerm_public_ip.public_ip.ip_address}"
  sensitive = true 
}

output "username" {
  value = upper(azurerm_linux_virtual_machine.vm.admin_username)
}

output "nifi_https_url" {
  value       = "https://${azurerm_linux_virtual_machine.vm.public_ip_address}:8443/nifi"
  description = "NiFi HTTPS URL (check terraform.tfvars for credentials)"
  sensitive   = true 
}

output "nifi_registry_url" {
  value       = "http://${azurerm_linux_virtual_machine.vm.public_ip_address}:18080/nifi-registry"
  description = "NiFi Registry URL"
  sensitive   = true 
}

output "service_info" {
  value       = <<-EOT
  
  === Docker Services on VM ===
  NiFi HTTP:       http://${azurerm_linux_virtual_machine.vm.public_ip_address}:8080/nifi
  NiFi HTTPS:      https://${azurerm_linux_virtual_machine.vm.public_ip_address}:8443/nifi
  NiFi Registry:   http://${azurerm_linux_virtual_machine.vm.public_ip_address}:18080/nifi-registry

  SSH: ssh azureuser@${azurerm_linux_virtual_machine.vm.public_ip_address}
  EOT
  description = "Complete service information"
  sensitive   = true
}