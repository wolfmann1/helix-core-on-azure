# Checkpoint offsite copy + restore verification.
#
# The verification job is the point. Most estates have checkpoints nobody has
# ever restored; the first restore attempt then happens during the outage.

resource "azurerm_role_assignment" "checkpoint_writer" {
  for_each             = toset(var.node_principal_ids)
  scope                = var.checkpoint_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}

# TODO(chris): restore-verification runner.
# Shape: a small spot VM (or Container App job) that on schedule pulls the
# newest checkpoint from blob, runs `p4d -jr` into a scratch P4ROOT, runs
# `p4d -xv` to verify, emits a custom metric, and destroys itself. Emitting
# the metric is what lets modules/observability alert when verification has
# not passed in N days.
