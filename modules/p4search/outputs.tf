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

output "data_disks" {
  description = "Volumes attached to this node after tier minimums were applied."
  value       = module.node.data_disks
}
