# Offsite checkpoint destination and the Key Vault holding the estate's
# secrets. Kept separate from the Terraform state account, which has different
# access patterns and a different set of principals.

resource "random_string" "sa" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_storage_account" "checkpoints" {
  name                            = replace("${var.name_prefix}ckpt${random_string.sa.result}", "-", "")
  location                        = var.location
  resource_group_name             = var.resource_group_name
  account_tier                    = "Standard"
  account_replication_type        = var.checkpoint_replication
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false
  tags                            = var.tags

  blob_properties {
    versioning_enabled = true
    delete_retention_policy { days = 30 }
  }
}

resource "azurerm_storage_container" "checkpoints" {
  name                  = "checkpoints"
  storage_account_id    = azurerm_storage_account.checkpoints.id
  container_access_type = "private"
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                          = "${var.name_prefix}-kv-${random_string.sa.result}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = false
  tags                          = var.tags
}
