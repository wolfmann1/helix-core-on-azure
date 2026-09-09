# dev — one commit server, nothing else. The cheapest thing that is still
# a real Perforce server. Used to iterate on provisioning scripts.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    time    = { source = "hashicorp/time", version = "~> 0.12" }
  }
}

provider "azurerm" {
  # The provider polls a new storage account's data plane to confirm the Blob
  # service is up, and does that with key-based auth unless told otherwise.
  # Both storage accounts here set shared_access_key_enabled = false, so that
  # poll returns "403 Key based authentication is not permitted on this storage
  # account" and the create fails after the account already exists.
  # storage_use_azuread makes every data-plane call use Entra ID instead.
  storage_use_azuread = true

  features {}
}

locals {
  prefix = "p4-stage"
  tags   = { environment = "stage", project = "helix-core-on-azure", owner = "chris" }

  # Short region codes, used in node names.
  #
  # A VM's system-assigned identity is a service principal in Entra ID stamped
  # with the VM's region, and it outlives the VM. Recreating a VM with the same
  # resource ID in a different region fails with
  # AlreadyExistServicePrincipalInDifferentRegion, and the principal cannot be
  # deleted directly because the resource provider owns it. Putting the region
  # in the name keeps resource IDs distinct per region, so a region move never
  # collides.
  region_code = {
    canadacentral = "cac"
    canadaeast    = "cae"
    westus2       = "wus2"
    westus3       = "wus3"
    eastus2       = "eus2"
  }
  loc    = lookup(local.region_code, var.location, var.location)
  dr_loc = var.dr_location == "" ? "" : lookup(local.region_code, var.dr_location, var.dr_location)
}

resource "azurerm_resource_group" "this" {
  name     = "${local.prefix}-rg"
  location = var.location
  tags     = local.tags
}

module "network" {
  source              = "../../modules/network"
  enable_nat_gateway  = var.enable_nat_gateway
  name_prefix         = local.prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

module "storage" {
  source                     = "../../modules/storage"
  key_vault_purge_protection = var.key_vault_purge_protection
  name_prefix                = local.prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

module "commit" {
  source               = "../../modules/commit-server"
  name                 = "${local.prefix}-${local.loc}-commit-01"
  location             = var.location
  resource_group_name  = azurerm_resource_group.this.name
  subnet_id            = module.network.subnet_ids["commit"]
  vm_size              = var.vm_size
  ssh_public_key       = var.ssh_public_key
  install_sdp          = var.install_sdp
  key_vault_id           = module.storage.key_vault_id
  grant_key_vault_access = true
  disk_tier            = var.disk_tier
  disk_sizes_gb        = var.disk_sizes_gb
  split_metadata       = var.split_metadata
  separate_sdp_volumes = var.separate_sdp_volumes
  serverlocks_tmpfs_mb = var.serverlocks_tmpfs_mb
  zone                 = var.zone
  tags                 = local.tags
}

module "observability" {
  source              = "../../modules/observability"
  name_prefix         = local.prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  alert_email         = var.alert_email
  tags                = local.tags
}

# ---- optional tiers, driven by tfvars -------------------------------------

module "edge" {
  source               = "../../modules/edge-server"
  count                = var.edge_count
  name                 = "${local.prefix}-${local.loc}-edge-${format("%02d", count.index + 1)}"
  location             = var.location
  resource_group_name  = azurerm_resource_group.this.name
  subnet_id            = module.network.subnet_ids["edge"]
  vm_size              = var.vm_size
  ssh_public_key       = var.ssh_public_key
  install_sdp          = var.install_sdp
  commit_host          = module.commit.private_ip
  key_vault_id           = module.storage.key_vault_id
  grant_key_vault_access = true
  disk_tier            = var.disk_tier
  disk_sizes_gb        = var.disk_sizes_gb
  split_metadata       = var.split_metadata
  separate_sdp_volumes = var.separate_sdp_volumes
  serverlocks_tmpfs_mb = var.serverlocks_tmpfs_mb
  zone                 = var.zone
  tags                 = local.tags
}

module "proxy" {
  source               = "../../modules/proxy"
  for_each             = var.proxy_sites
  name                 = "${local.prefix}-${local.loc}-proxy-${each.key}"
  location             = var.location
  resource_group_name  = azurerm_resource_group.this.name
  subnet_id            = module.network.subnet_ids["proxy"]
  vm_size              = each.value.vm_size
  ssh_public_key       = var.ssh_public_key
  install_sdp          = false
  commit_host          = module.commit.private_ip
  disk_tier            = var.disk_tier
  disk_sizes_gb        = var.disk_sizes_gb
  split_metadata       = var.split_metadata
  separate_sdp_volumes = var.separate_sdp_volumes
  serverlocks_tmpfs_mb = var.serverlocks_tmpfs_mb
  zone                 = var.zone
  tags                 = merge(local.tags, { site = each.key })
}

module "broker" {
  source               = "../../modules/broker"
  name                 = "${local.prefix}-${local.loc}-broker-01"
  location             = var.location
  resource_group_name  = azurerm_resource_group.this.name
  subnet_id            = module.network.subnet_ids["app"]
  vm_size              = var.vm_size
  ssh_public_key       = var.ssh_public_key
  install_sdp          = false
  commit_host          = module.commit.private_ip
  disk_tier            = var.disk_tier
  disk_sizes_gb        = var.disk_sizes_gb
  split_metadata       = var.split_metadata
  separate_sdp_volumes = var.separate_sdp_volumes
  serverlocks_tmpfs_mb = var.serverlocks_tmpfs_mb
  zone                 = var.zone
  tags                 = local.tags
}

module "swarm" {
  source               = "../../modules/swarm"
  count                = var.enable_swarm ? 1 : 0
  name                 = "${local.prefix}-${local.loc}-swarm-01"
  location             = var.location
  resource_group_name  = azurerm_resource_group.this.name
  subnet_id            = module.network.subnet_ids["app"]
  vm_size              = var.vm_size
  ssh_public_key       = var.ssh_public_key
  install_sdp          = false
  commit_host          = module.commit.private_ip
  key_vault_id           = module.storage.key_vault_id
  grant_key_vault_access = true
  disk_tier            = var.disk_tier
  disk_sizes_gb        = var.disk_sizes_gb
  split_metadata       = var.split_metadata
  separate_sdp_volumes = var.separate_sdp_volumes
  serverlocks_tmpfs_mb = var.serverlocks_tmpfs_mb
  zone                 = var.zone
  tags                 = local.tags
}

module "p4search" {
  source               = "../../modules/p4search"
  count                = var.enable_p4search ? 1 : 0
  name                 = "${local.prefix}-${local.loc}-search-01"
  location             = var.location
  resource_group_name  = azurerm_resource_group.this.name
  subnet_id            = module.network.subnet_ids["app"]
  vm_size              = var.p4search_vm_size
  ssh_public_key       = var.ssh_public_key
  install_sdp          = false
  commit_host          = module.commit.private_ip
  disk_tier            = var.disk_tier
  disk_sizes_gb        = var.disk_sizes_gb
  split_metadata       = var.split_metadata
  separate_sdp_volumes = var.separate_sdp_volumes
  serverlocks_tmpfs_mb = var.serverlocks_tmpfs_mb
  zone                 = var.zone
  tags                 = local.tags
}

module "backup" {
  source                = "../../modules/backup"
  name_prefix           = local.prefix
  location              = var.location
  resource_group_name   = azurerm_resource_group.this.name
  checkpoint_account_id = module.storage.checkpoint_account_id
  node_principal_ids    = compact(concat([module.commit.principal_id], [for e in module.edge : e.principal_id]))
  tags                  = local.tags
}
