variable "name_prefix" {
  description = "Prefix for backup resource names."
  type        = string
}
variable "location" {
  description = "Azure region."
  type        = string
}
variable "resource_group_name" {
  description = "Resource group for backup resources."
  type        = string
}
variable "node_principal_ids" {
  description = "Managed identity principal IDs granted write access to the checkpoint container."
  type        = list(string)
  default     = []
}
variable "checkpoint_account_id" {
  description = "Storage account holding checkpoints."
  type        = string
}
variable "verify_restore_enabled" {
  description = "Run the scheduled restore-verification job, which exercises the restore procedure against current checkpoints. Leave enabled."
  type        = bool
  default     = true
}
variable "verify_schedule_cron" {
  description = "Cron for the restore-verification job."
  type        = string
  default     = "0 4 * * 0"
}
variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
