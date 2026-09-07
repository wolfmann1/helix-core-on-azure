output "workspace_id" {
  description = "Log Analytics workspace resource ID."
  value       = azurerm_log_analytics_workspace.this.id
}
output "alert_names" {
  description = "Names of the alert rules created, for the runbook."
  value       = keys(local.alerts)
}
