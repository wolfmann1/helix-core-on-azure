output "private_ip" {
  description = "Private IP of the node."
  value       = module.node.private_ip
}
output "principal_id" {
  description = "Managed identity principal ID of the node."
  value       = module.node.principal_id
}
output "name" {
  description = "Node name."
  value       = module.node.name
}
