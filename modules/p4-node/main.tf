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
  ]))
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
  for_each             = var.data_disks
  name                 = "${var.name}-${each.key}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = each.value.tier
  create_option        = "Empty"
  disk_size_gb         = each.value.size_gb
  tags                 = merge(var.tags, { volume = each.key })
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  for_each           = var.data_disks
  managed_disk_id    = azurerm_managed_disk.data[each.key].id
  virtual_machine_id = azurerm_linux_virtual_machine.this.id
  lun                = each.value.lun
  caching            = each.key == "p4db" ? "ReadOnly" : "None"
}

resource "azurerm_key_vault_access_policy" "this" {
  count        = var.key_vault_id == "" ? 0 : 1
  key_vault_id = var.key_vault_id
  tenant_id    = azurerm_linux_virtual_machine.this.identity[0].tenant_id
  object_id    = azurerm_linux_virtual_machine.this.identity[0].principal_id

  secret_permissions = ["Get", "List"]
}
