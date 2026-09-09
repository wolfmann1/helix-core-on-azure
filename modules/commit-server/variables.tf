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
  default     = "Standard_B2ats_v2"
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
  description = "Per-volume size overrides in GiB (p4db, p4db2, p4logs, p4depots, p4, p4ckps). Defaults are set in modules/p4-node and sized for a lab."
  type        = map(number)
  default     = {}
}
variable "tags" {
  description = "Tags applied to the node."
  type        = map(string)
  default     = {}
}
variable "disk_tier" {
  description = "Managed disk type: premium, standard, premium_v2 or hdd. See modules/p4-node for the size floors each implies."
  type        = string
  default     = "standard"
}
variable "split_metadata" {
  description = "Place metadata on two volumes (p4db and p4db2) rather than one."
  type        = bool
  default     = true
}
variable "separate_sdp_volumes" {
  description = "Give /p4 and /p4ckps their own volumes rather than placing them on p4depots."
  type        = bool
  default     = false
}
variable "serverlocks_tmpfs_mb" {
  description = "Size of the tmpfs mounted for server lock files. 0 skips it."
  type        = number
  default     = 1024
}
variable "zone" {
  description = "Availability zone. Required when disk_tier is premium_v2 in most regions."
  type        = string
  default     = null
}
