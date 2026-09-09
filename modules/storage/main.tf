# Offsite checkpoint destination and the Key Vault holding the estate's
# secrets. Kept separate from the Terraform state account, which has different
# access patterns and a different set of principals.

resource "random_string" "sa" {
  length  = 6
  upper   = false
  special = false
}

# prevent_destroy is deliberately absent. These environments are applied on
# demand and torn down with scripts/teardown.ps1, and prevent_destroy would
# block that. The state backend in bootstrap/ does set it, because destroying
# state is never routine. Set checkpoint_replication and add the lifecycle
# block by hand for an estate holding real depot content.
# tflint-ignore: azurerm_resources_missing_prevent_destroy
resource "azurerm_storage_account" "checkpoints" {
  # checkov:skip=CKV_AZURE_206:LRS is a deliberate cost choice for a lab that is rebuilt often. Set checkpoint_replication to GRS for anything holding real depot content.
  # checkov:skip=CKV2_AZURE_1:Customer-managed key encryption needs a Key Vault key and rotation policy that this environment does not warrant. Platform-managed keys are in use.
  # checkov:skip=CKV_AZURE_33:Queue service logging is not relevant; this account holds blobs only.
  # checkov:skip=CKV2_AZURE_33:Private endpoints are not created here yet. Public network access is disabled instead. See the TODO below.
  name                            = replace("${var.name_prefix}ckpt${random_string.sa.result}", "-", "")
  location                        = var.location
  resource_group_name             = var.resource_group_name
  account_tier                    = "Standard"
  account_replication_type        = var.checkpoint_replication
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false
  # Force Entra ID authentication. Node identities write checkpoints through
  # RBAC, so no account key is needed anywhere.
  shared_access_key_enabled = false
  tags                      = var.tags

  sas_policy {
    expiration_period = "00.01:00:00"
    expiration_action = "Log"
  }

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
  }
}

# tflint-ignore: azurerm_resources_missing_prevent_destroy
resource "azurerm_storage_container" "checkpoints" {
  # checkov:skip=CKV2_AZURE_21:Blob read logging on the checkpoint container has no audience here and adds cost; write and delete operations are already captured by the account's activity log.
  name                  = "checkpoints"
  storage_account_id    = azurerm_storage_account.checkpoints.id
  container_access_type = "private"
}

data "azurerm_client_config" "current" {}

# Same reason as the storage account above. Note that purge_protection_enabled
# is true, so a destroyed vault is recoverable within the soft-delete window.
# tflint-ignore: azurerm_resources_missing_prevent_destroy
resource "azurerm_key_vault" "this" {
  # checkov:skip=CKV2_AZURE_32:Private endpoints are not created here yet. Public network access is disabled and network_acls default to Deny. See the TODO below.
  name                          = "${var.name_prefix}-kv-${random_string.sa.result}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = false
  tags                          = var.tags

  # Deny by default. Azure services that need access are allowed by bypass
  # rather than by opening the vault to a network range.
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}

# TODO(chris): private endpoints for the Key Vault and the checkpoint storage
# account, with the matching private DNS zones and VNet links. Public network
# access is disabled on both today, which closes the exposure, but nodes inside
# the VNet cannot reach either service until the endpoints exist. This is the
# next real piece of work in this module, and it is why the two CKV2 checks
# above are skipped rather than passing.
