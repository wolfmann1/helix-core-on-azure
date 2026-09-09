# Cross-region standby replica running journalcopy. The DR spine.
# Thin wrapper over modules/p4-node. The primitive owns VM, disks, identity
# and provisioning; this module owns the role's opinionated defaults.

module "node" {
  source = "../p4-node"

  name                 = var.name
  role                 = "standby"
  location             = var.location
  resource_group_name  = var.resource_group_name
  subnet_id            = var.subnet_id
  vm_size              = var.vm_size
  ssh_public_key       = var.ssh_public_key
  install_sdp          = var.install_sdp
  commit_host          = var.commit_host
  key_vault_id           = var.key_vault_id
  grant_key_vault_access = var.grant_key_vault_access
  disk_tier            = var.disk_tier
  disk_sizes_gb        = var.disk_sizes_gb
  split_metadata       = var.split_metadata
  separate_sdp_volumes = var.separate_sdp_volumes
  serverlocks_tmpfs_mb = var.serverlocks_tmpfs_mb
  zone                 = var.zone
  tags                 = var.tags
}
