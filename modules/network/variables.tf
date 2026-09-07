variable "name_prefix" {
  description = "Prefix applied to all network resource names, e.g. p4-dev."
  type        = string
}

variable "location" {
  description = "Azure region for the virtual network."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that will hold the network resources."
  type        = string
}

variable "address_space" {
  description = "CIDR block for the virtual network."
  type        = string
  default     = "10.40.0.0/16"
}

variable "subnet_prefixes" {
  description = "CIDR per subnet. The commit, edge and proxy tiers are separated because proxies face the least trusted networks and the commit server the most trusted."
  type        = map(string)
  default = {
    commit = "10.40.1.0/24"
    edge   = "10.40.2.0/24"
    proxy  = "10.40.3.0/24"
    app    = "10.40.4.0/24" # Swarm, P4 Search
    mgmt   = "10.40.250.0/26"
  }
}

variable "p4_port" {
  description = "TCP port p4d listens on."
  type        = number
  default     = 1666
}

variable "enable_bastion" {
  description = "Deploy Azure Bastion. Off by default in dev to keep the footprint minimal; there are no public IPs on p4d hosts either way."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
