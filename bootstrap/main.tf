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
  }
}

provider "azurerm" {
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

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
  }
}

resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

output "storage_account_name" {
  description = "Paste this into every envs/*/backend.tf."
  value       = azurerm_storage_account.state.name
}
