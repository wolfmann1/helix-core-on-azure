output "vnet_id" {
  description = "Resource ID of the virtual network."
  value       = azurerm_virtual_network.this.id
}

output "subnet_ids" {
  description = "Map of subnet name to subnet resource ID."
  value       = { for k, v in azurerm_subnet.this : k => v.id }
}

output "subnet_prefixes" {
  description = "Map of subnet name to CIDR, for downstream NSG rules."
  value       = var.subnet_prefixes
}

output "nat_gateway_public_ip" {
  description = "Outbound IP when a NAT gateway is deployed. Empty otherwise, in which case egress uses Azure's default outbound access and the address is Microsoft-owned and not stable."
  value       = var.enable_nat_gateway ? azurerm_public_ip.nat[0].ip_address : ""
}
