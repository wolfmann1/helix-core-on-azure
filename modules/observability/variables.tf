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
    volume_free_pct_warn      = number
    volume_free_pct_page      = number
    replica_lag_seconds       = number
    submit_p95_seconds        = number
    blocked_command_secs      = number
    license_expiry_days       = number
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

variable "custom_log_tables_ready" {
  description = <<-EOT
    Deploy the alerts whose queries read custom log tables (P4Commands_CL,
    P4Monitor_CL, P4Replication_CL, P4Proxy_CL, P4License_CL,
    P4RestoreVerify_CL).

    Azure validates a scheduled query rule's KQL at creation time and rejects a
    query against a table that does not exist, so these cannot be created until
    something is ingesting into them. That work is not built yet: it needs a
    data collection rule per table and an agent-side collector that parses the
    Perforce structured logs and p4 monitor output.

    Leave false until ingestion exists. Five alerts against built-in tables
    (InsightsMetrics, Syslog, Heartbeat) deploy either way.
  EOT
  type    = bool
  default = false
}
