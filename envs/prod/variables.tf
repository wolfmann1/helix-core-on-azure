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

variable "p4search_vm_size" {
  description = <<-EOT
    VM size for the P4 Search node. Perforce states 4 vCPU and 8 GB RAM per
    component for a small site, so this is larger than every other role here.

    The az104-lab guardrails deny any SKU outside Standard_B2pts_v2,
    Standard_B2ats_v2, Standard_B1s and Standard_B2s. Enabling P4 Search
    therefore requires widening allowedVmSkus in az104-lab/guardrails.bicep and
    redeploying, or accepting an undersized node that will not index reliably.
  EOT
  type        = string
  default     = "Standard_D2as_v5"
}

variable "vm_size" {
  description = <<-EOT
    VM size for the Perforce roles.

    A SKU being permitted by policy does not mean it has capacity. Azure
    returns "SkuNotAvailable ... Capacity Restrictions" per region and zone, and
    availability changes over time. Check before changing this:

      az vm list-skus --location canadacentral --size Standard_B --all -o table

    Rows with a restriction of NotAvailableForSubscription cannot be deployed.
  EOT
  type    = string
  default = "Standard_B2ats_v2"
}

variable "key_vault_purge_protection" {
  description = "Enable Key Vault purge protection. False lets a torn-down environment be rebuilt under the same vault name; see modules/storage."
  type        = bool
  default     = false
}

variable "enable_nat_gateway" {
  description = "Deploy a NAT gateway and make the Perforce subnets private. Bills hourly; see modules/network for the tradeoff against Azure's default outbound access."
  type        = bool
  default     = false
}
