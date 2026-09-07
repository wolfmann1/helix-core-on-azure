# P4P proxy — file content cache only, no metadata volume.
# Thin wrapper over modules/p4-node. The primitive owns VM, disks, identity
# and provisioning; this module owns the role's opinionated defaults.

module "node" {
  source = "../p4-node"

  name                = var.name
  role                = "proxy"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  vm_size             = var.vm_size
  ssh_public_key      = var.ssh_public_key
  install_sdp         = var.install_sdp
  commit_host         = var.commit_host
  key_vault_id        = var.key_vault_id
  data_disks          = {
    p4depots = { size_gb = lookup(var.disk_sizes_gb, "p4depots", 64), tier = "StandardSSD_LRS", lun = 0 }
  }
  tags                = var.tags
}
