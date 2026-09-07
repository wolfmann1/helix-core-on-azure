# P4 Search (fronts Elasticsearch). Opt-in: its own floor is 4 vCPU / 8GB per component.
# Thin wrapper over modules/p4-node. The primitive owns VM, disks, identity
# and provisioning; this module owns the role's opinionated defaults.

module "node" {
  source = "../p4-node"

  name                = var.name
  role                = "p4search"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  vm_size             = var.vm_size
  ssh_public_key      = var.ssh_public_key
  install_sdp         = var.install_sdp
  commit_host         = var.commit_host
  key_vault_id        = var.key_vault_id
  data_disks          = {}
  tags                = var.tags
}
