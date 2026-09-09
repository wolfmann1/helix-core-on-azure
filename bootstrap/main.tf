# Bootstrap — creates the Terraform state backend.
#
# The state backend cannot store its own state, so this configuration is
# applied once, by hand, using local state. Keep that local state somewhere
# private; it is not committed here.

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

variable "location" {
  description = "Region for the state backend."
  type        = string
  default     = "canadacentral"
}

resource "random_string" "s" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "state" {
  name     = "p4-tfstate-rg"
  location = var.location
}

resource "azurerm_storage_account" "state" {
  # checkov:skip=CKV_AZURE_206:LRS is deliberate. This account holds Terraform state for a lab; the cost of GRS is not justified and state is reproducible.
  # checkov:skip=CKV2_AZURE_1:Customer-managed keys would require a Key Vault that this configuration bootstraps before any Key Vault exists.
  # checkov:skip=CKV_AZURE_33:Queue service logging is not relevant; this account holds blobs only.
  # checkov:skip=CKV_AZURE_59:Public network access stays enabled because the GitHub Actions runners reach this account over the internet. Anonymous access is disabled and account keys are turned off, so access requires an Entra ID identity.
  # checkov:skip=CKV2_AZURE_33:Same reason. A private endpoint would require a self-hosted runner inside the VNet.
  name                            = "p4tfstate${random_string.s.result}"
  resource_group_name             = azurerm_resource_group.state.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false # force Entra ID auth; no account keys

  sas_policy {
    expiration_period = "00.01:00:00"
    expiration_action = "Log"
  }

  # Destroying this account destroys the state for every environment. Removing
  # it is a deliberate act that should require editing this file first.
  lifecycle {
    prevent_destroy = true
  }

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
  }
}

resource "time_sleep" "rbac_propagation" {
  depends_on      = [azurerm_role_assignment.state_operator]
  create_duration = "60s"
}

resource "azurerm_storage_container" "state" {
  # checkov:skip=CKV2_AZURE_21:Blob read logging on the state container has no audience here and adds cost; write and delete operations are already captured by the account's activity log.
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"

  # Creating the container is a data-plane call. It needs the role assignment
  # above to have propagated, which is why the wait exists.
  depends_on = [time_sleep.rbac_propagation]

  lifecycle {
    prevent_destroy = true
  }
}

data "azurerm_client_config" "current" {}

# The backend sets use_azuread_auth and this account has account keys disabled,
# so Terraform reaches the blob data plane as whoever is signed in. Control-plane
# roles such as Owner do not grant data-plane access; without this assignment,
# "terraform init" in envs/* fails with a 403 on the state container.
resource "azurerm_role_assignment" "state_operator" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

output "state_operator_principal_id" {
  description = "Principal granted data-plane access to the state container. The pipeline's OIDC identity needs the same role; see docs/GETTING-STARTED.md."
  value       = data.azurerm_client_config.current.object_id
}

output "storage_account_name" {
  description = "Paste this into every envs/*/backend.tf."
  value       = azurerm_storage_account.state.name
}
