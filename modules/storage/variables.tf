variable "name_prefix" {
  description = "Prefix for storage resource names."
  type        = string
}
variable "location" {
  description = "Azure region."
  type        = string
}
variable "resource_group_name" {
  description = "Resource group for storage resources."
  type        = string
}
variable "checkpoint_replication" {
  description = "Replication for the offsite checkpoint account. GRS in prod; LRS is enough for a lab."
  type        = string
  default     = "LRS"
}
variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}

variable "key_vault_purge_protection" {
  description = <<-EOT
    Enable Key Vault purge protection.

    Leave false for environments that are torn down and rebuilt. With purge
    protection on, a deleted vault cannot be purged early, so its name stays
    reserved for the whole soft-delete retention period and a rebuild that
    generates the same name fails. Azure also does not allow purge protection to
    be turned off once a vault has it, so the setting is effectively permanent
    per vault.

    Set true in prod, where the point is that a deleted vault is recoverable.
  EOT
  type    = bool
  default = false
}

variable "key_vault_soft_delete_days" {
  description = "Soft-delete retention for the Key Vault. Azure's minimum is 7. Only matters when a vault is deleted."
  type        = number
  default     = 7
}
