variable "name" {
  description = "Node name."
  type        = string
}
variable "location" {
  description = "Azure region."
  type        = string
}
variable "resource_group_name" {
  description = "Resource group for the node."
  type        = string
}
variable "subnet_id" {
  description = "Subnet the node attaches to."
  type        = string
}
variable "vm_size" {
  description = "VM size. Default is the smallest that runs this role."
  type        = string
  default     = "Standard_B2s"
}
variable "ssh_public_key" {
  description = "SSH public key for the admin account."
  type        = string
}
variable "install_sdp" {
  description = "Install the Perforce Server Deployment Package."
  type        = bool
  default     = true
}
variable "commit_host" {
  description = "Commit server host. Required for all roles except commit."
  type        = string
  default     = ""
}
variable "key_vault_id" {
  description = "Key Vault granted to this node's managed identity."
  type        = string
  default     = ""
}
variable "disk_sizes_gb" {
  description = "Override data disk sizes by volume label."
  type        = map(number)
  default     = {}
}
variable "tags" {
  description = "Tags applied to the node."
  type        = map(string)
  default     = {}
}
