terraform {
  backend "azurerm" {
    resource_group_name  = "p4-tfstate-rg"
    storage_account_name = "REPLACE_ME_FROM_BOOTSTRAP"
    container_name       = "tfstate"
    key                  = "stage.terraform.tfstate"
    use_azuread_auth     = true
  }
}
