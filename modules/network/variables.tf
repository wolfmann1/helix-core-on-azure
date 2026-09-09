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

variable "enable_nat_gateway" {
  description = <<-EOT
    Deploy a NAT gateway and make the Perforce subnets private.

    The nodes need outbound internet: apt for packages, and the SDP download
    from the Perforce workshop. Something has to provide it, and there are only
    two honest choices here, because giving a Perforce host a public IP is not
    one of them.

    false (default): subnets keep default outbound access. Azure assigns a
    Microsoft-owned outbound IP that can change without notice. It costs
    nothing, and Azure retired it for new virtual networks on 31 March 2026 --
    new VNets now default to private subnets, and the provider setting this to
    true is what keeps it working here. The portal raises an advisory about it.

    true: a NAT gateway provides outbound through an IP you own, and the
    subnets are set private. This is the correct design and what a real estate
    should use. It bills hourly whether or not anything is sending traffic,
    like Bastion, so it is off in dev and stage and on in prod, which is
    applied on demand and destroyed.
  EOT
  type    = bool
  default = false
}

variable "nat_gateway_zones" {
  description = "Availability zones for the NAT gateway and its public IP. Empty for a regional (non-zonal) deployment."
  type        = list(string)
  default     = []
}
