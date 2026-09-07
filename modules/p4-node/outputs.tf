output "id" {
  description = "Resource ID of the virtual machine."
  value       = azurerm_linux_virtual_machine.this.id
}

output "name" {
  description = "VM name."
  value       = azurerm_linux_virtual_machine.this.name
}

output "private_ip" {
  description = "Private IP address of the node's NIC."
  value       = azurerm_network_interface.this.private_ip_address
}

output "principal_id" {
  description = "System-assigned managed identity principal ID, for RBAC grants."
  value       = azurerm_linux_virtual_machine.this.identity[0].principal_id
}
