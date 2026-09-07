variable "location" {
  description = "Primary Azure region."
  type        = string
}
variable "dr_location" {
  description = "Secondary region for the standby replica."
  type        = string
  default     = ""
}
variable "ssh_public_key" {
  description = "SSH public key for node admin accounts."
  type        = string
}
variable "alert_email" {
  description = "Destination for alert notifications."
  type        = string
}
variable "edge_count" {
  description = "Number of edge servers."
  type        = number
  default     = 0
}
variable "proxy_sites" {
  description = "Proxy sites to deploy, keyed by site name."
  type        = map(object({ vm_size = string }))
  default     = {}
}
variable "enable_swarm" {
  description = "Deploy P4 Code Review."
  type        = bool
  default     = false
}
variable "enable_p4search" {
  description = "Deploy P4 Search. Off by default — Elasticsearch's floor is 4 vCPU / 8GB per component."
  type        = bool
  default     = false
}
variable "enable_standby" {
  description = "Deploy the cross-region standby replica."
  type        = bool
  default     = false
}
variable "install_sdp" {
  description = "Install the Perforce SDP on Perforce nodes."
  type        = bool
  default     = true
}

variable "disk_tier" {
  description = "Managed disk type for all Perforce data disks: premium, standard, premium_v2 or hdd."
  type        = string
  default     = "standard"
}
variable "disk_sizes_gb" {
  description = "Per-volume size overrides in GiB (p4db, p4db2, p4logs, p4depots, p4, p4ckps). Empty uses the lab defaults in modules/p4-node."
  type        = map(number)
  default     = {}
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
