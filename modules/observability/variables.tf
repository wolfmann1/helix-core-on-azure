variable "name_prefix" {
  description = "Prefix for observability resource names."
  type        = string
}
variable "location" {
  description = "Azure region."
  type        = string
}
variable "resource_group_name" {
  description = "Resource group for observability resources."
  type        = string
}
variable "monitored_vm_ids" {
  description = "VM resource IDs to associate with the data collection rule."
  type        = list(string)
  default     = []
}
variable "alert_email" {
  description = "Email address for the action group."
  type        = string
}
variable "log_retention_days" {
  description = "Log Analytics retention. 30 is the cheap floor; audit use cases want more."
  type        = number
  default     = 30
}
variable "thresholds" {
  description = "Alert thresholds. Defaults come from what actually predicts a Perforce outage, not from generic infrastructure monitoring."
  type = object({
    volume_free_pct_warn  = number
    volume_free_pct_page  = number
    replica_lag_seconds   = number
    submit_p95_seconds    = number
    blocked_command_secs  = number
    license_expiry_days   = number
    restore_verify_stale_days = number
  })
  default = {
    volume_free_pct_warn      = 20
    volume_free_pct_page      = 10
    replica_lag_seconds       = 60
    submit_p95_seconds        = 5
    blocked_command_secs      = 300
    license_expiry_days       = 30
    restore_verify_stale_days = 8
  }
}
variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
