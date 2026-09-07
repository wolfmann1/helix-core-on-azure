# Checkpoint offsite copy and restore verification.
#
# The verification job restores each checkpoint into a scratch instance so the
# restore procedure is exercised routinely rather than for the first time
# during an outage.

resource "azurerm_role_assignment" "checkpoint_writer" {
  for_each             = toset(var.node_principal_ids)
  scope                = var.checkpoint_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}

# TODO(chris): restore-verification runner.
# Approach: a small spot VM or Container App job that, on schedule, pulls the
# newest checkpoint from blob storage, runs `p4d -jr` into a scratch P4ROOT,
# runs `p4d -xv` to verify, emits a custom metric, and shuts down. The metric
# is what modules/observability alerts on when verification goes stale.
