output "key_vault_id" {
  description = "Key Vault resource ID, granted to node managed identities."
  value       = azurerm_key_vault.this.id
}
output "checkpoint_account_name" {
  description = "Storage account holding offsite checkpoints."
  value       = azurerm_storage_account.checkpoints.name
}
output "checkpoint_container" {
  description = "Blob container for checkpoints."
  value       = azurerm_storage_container.checkpoints.name
}
output "checkpoint_account_id" {
  description = "Storage account resource ID, for RBAC grants to node identities."
  value       = azurerm_storage_account.checkpoints.id
}
