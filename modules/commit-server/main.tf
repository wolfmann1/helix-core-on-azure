# Commit (master) server — authoritative metadata and archive.
# Thin wrapper over modules/p4-node. The primitive owns VM, disks, identity
# and provisioning; this module owns the role's opinionated defaults.

module "node" {
  source = "../p4-node"

  name                = var.name
  role                = "commit"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  vm_size             = var.vm_size
  ssh_public_key      = var.ssh_public_key
  install_sdp         = var.install_sdp
  commit_host         = var.commit_host
  key_vault_id        = var.key_vault_id
  data_disks          = {
    p4db     = { size_gb = lookup(var.disk_sizes_gb, "p4db", 32),      tier = "Premium_LRS",     lun = 0 }
    p4logs   = { size_gb = lookup(var.disk_sizes_gb, "p4logs", 32),    tier = "Premium_LRS",     lun = 1 }
    p4depots = { size_gb = lookup(var.disk_sizes_gb, "p4depots", 64),  tier = "StandardSSD_LRS", lun = 2 }
  }
  tags                = var.tags
}
