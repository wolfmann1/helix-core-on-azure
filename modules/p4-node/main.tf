locals {
  # The same provisioning entry point is used by Azure cloud-init and by the
  # Hyper-V path in local/hyperv. Azure-specific configuration stays in
  # Terraform; Perforce configuration stays in provisioning/.
  provision_args = join(" ", compact([
    "--role ${var.role}",
    "--install-sdp ${var.install_sdp}",
    "--sdp-instance ${var.sdp_instance}",
    "--p4port ${var.p4_port}",
    var.commit_host != "" ? "--commit-host ${var.commit_host}" : "",
    "--serverlocks-mb ${var.serverlocks_tmpfs_mb}",
  ]))

  storage_account_type = {
    premium    = "Premium_LRS"
    standard   = "StandardSSD_LRS"
    premium_v2 = "PremiumV2_LRS"
    hdd        = "Standard_LRS"
  }[var.disk_tier]

  # Azure will not allocate a disk below its type's smallest tier: 4 GiB for
  # Premium SSD v1 and Standard SSD, 32 GiB for Standard HDD. Premium SSD v2
  # allocates from 1 GiB in 1 GiB increments. Requested sizes are rounded up
  # to the floor rather than rejected.
  tier_min_gb = {
    premium    = 4
    standard   = 4
    premium_v2 = 1
    hdd        = 32
  }[var.disk_tier]

  # Defaults sized for a lab that is rebuilt often.
  default_sizes = {
    p4db     = 2
    p4db2    = 2
    p4logs   = 2
    p4depots = 5
    p4       = 1
    p4ckps   = 1
  }
  requested_sizes = merge(local.default_sizes, var.disk_sizes_gb)

  metadata_volumes = var.split_metadata ? ["p4db", "p4db2"] : ["p4db"]
  sdp_volumes      = var.separate_sdp_volumes ? ["p4", "p4ckps"] : []

  # Which volumes each role needs. A proxy caches file content and holds no
  # metadata, so it gets one volume. Broker, Swarm and P4 Search hold no
  # Perforce data at all.
  role_volumes = {
    commit   = concat(local.metadata_volumes, ["p4logs", "p4depots"], local.sdp_volumes)
    edge     = concat(local.metadata_volumes, ["p4logs", "p4depots"], local.sdp_volumes)
    standby  = concat(local.metadata_volumes, ["p4logs", "p4depots"], local.sdp_volumes)
    proxy    = ["p4depots"]
    broker   = []
    swarm    = []
    p4search = []
  }
  volumes = local.role_volumes[var.role]

  data_disks = {
    for idx, vol in local.volumes : vol => {
      size_gb = max(local.requested_sizes[vol], local.tier_min_gb)
      lun     = idx
      # Premium SSD v2 does not support host caching. Elsewhere, metadata
      # benefits from ReadOnly caching; journal and archive writes do not.
      caching = var.disk_tier == "premium_v2" ? "None" : (
        startswith(vol, "p4db") ? "ReadOnly" : "None"
      )
    }
  }
}

resource "azurerm_network_interface" "this" {
  name                = "${var.name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    # No public_ip_address_id, by design, in every environment.
  }
}

resource "azurerm_linux_virtual_machine" "this" {
  name                            = var.name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  network_interface_ids           = [azurerm_network_interface.this.id]
  disable_password_authentication = true
  zone                            = var.zone
  tags                            = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = var.os_image.publisher
    offer     = var.os_image.offer
    sku       = var.os_image.sku
    version   = var.os_image.version
  }

  # System-assigned identity, so the node authenticates to Key Vault and blob
  # storage without a credential in custom_data or Terraform state.
  identity {
    type = "SystemAssigned"
  }

  custom_data = base64encode(templatefile("${path.module}/../../provisioning/cloud-init/node.yaml.tftpl", {
    provision_args = local.provision_args
    role           = var.role
  }))
}

resource "azurerm_managed_disk" "data" {
  for_each             = local.data_disks
  name                 = "${var.name}-${each.key}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = local.storage_account_type
  create_option        = "Empty"
  disk_size_gb         = each.value.size_gb
  zone                 = var.zone
  tags                 = merge(var.tags, { volume = each.key })
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  for_each           = local.data_disks
  managed_disk_id    = azurerm_managed_disk.data[each.key].id
  virtual_machine_id = azurerm_linux_virtual_machine.this.id
  lun                = each.value.lun
  caching            = each.value.caching
}

resource "azurerm_key_vault_access_policy" "this" {
  count        = var.key_vault_id == "" ? 0 : 1
  key_vault_id = var.key_vault_id
  tenant_id    = azurerm_linux_virtual_machine.this.identity[0].tenant_id
  object_id    = azurerm_linux_virtual_machine.this.identity[0].principal_id

  secret_permissions = ["Get", "List"]
}
