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
