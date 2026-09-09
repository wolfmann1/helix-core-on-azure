# Alert definitions. These target Perforce-specific signals rather than
# generic VM metrics. Tier 1 pages, tier 2 raises a ticket, tier 3 emails.

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.name_prefix}-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

resource "azurerm_monitor_action_group" "page" {
  name                = "${var.name_prefix}-ag-page"
  resource_group_name = var.resource_group_name
  short_name          = "p4page"
  email_receiver {
    name          = "primary"
    email_address = var.alert_email
  }
}

locals {
  # Each entry records why the alert exists, so the reasoning carries over
  # when the module is pointed at a different estate.
  #
  # "custom" marks an alert whose query reads a custom log table (the _CL
  # suffix). Azure validates the KQL when the rule is created and rejects a
  # query against a table that does not exist yet, so these cannot be deployed
  # until something is ingesting into them. See var.custom_log_tables_ready.
  alerts = {
    # ---- Tier 1: outage imminent or in progress -------------------------
    p4logs_free = {
      tier   = 1
      custom = false
      why    = "The journal cannot be written and p4d stops. Generic monitoring misses this because the metadata volume still looks healthy."
      kql    = "InsightsMetrics | where Name == 'FreeSpacePercentage' and Tags has 'p4logs' | summarize v=min(Val) by Computer"
      op     = "LessThan"
      thresh = var.thresholds.volume_free_pct_page
    }
    p4db_free = {
      tier   = 1
      custom = false
      why    = "A full metadata volume may require a checkpoint restore rather than freeing space and restarting."
      kql    = "InsightsMetrics | where Name == 'FreeSpacePercentage' and Tags has 'p4db' | summarize v=min(Val) by Computer"
      op     = "LessThan"
      thresh = var.thresholds.volume_free_pct_page
    }
    checkpoint_failed = {
      tier   = 1
      custom = false
      why    = "A missed checkpoint has no immediate impact, but determines how much data is recoverable during a restore."
      kql    = "Syslog | where SyslogMessage has 'checkpoint' and SyslogMessage has_any ('failed','error') | summarize v=count() by Computer"
      op     = "GreaterThan"
      thresh = 0
    }
    replica_lag = {
      tier   = 1
      custom = true
      why    = "Rising lag means the effective RPO differs from the documented one. This alert makes the RPO a measured value."
      kql    = "P4Replication_CL | summarize v=max(LagSeconds_d) by Computer"
      op     = "GreaterThan"
      thresh = var.thresholds.replica_lag_seconds
    }
    p4d_restart = {
      tier   = 1
      custom = false
      why    = "Unexplained restarts commonly precede a resource or memory problem by one to two weeks."
      kql    = "Heartbeat | summarize v=count() by Computer" # placeholder: replace with p4d uptime counter
      op     = "GreaterThan"
      thresh = 0
    }

    # ---- Tier 2: users already hurting ----------------------------------
    submit_latency_p95 = {
      tier   = 2
      custom = true
      why    = "The user-facing SLI. The tier 1 alerts are leading indicators for this one."
      kql    = "P4Commands_CL | where Command_s == 'user-submit' | summarize v=percentile(Duration_d, 95) by Computer"
      op     = "GreaterThan"
      thresh = var.thresholds.submit_p95_seconds
    }
    blocked_commands = {
      tier   = 2
      custom = true
      why    = "A single large sync holding a lock can block other users. p4 monitor shows this before users report it."
      kql    = "P4Monitor_CL | where Status_s == 'B' or Runtime_d > ${var.thresholds.blocked_command_secs} | summarize v=count() by Computer"
      op     = "GreaterThan"
      thresh = 0
    }
    connection_saturation = {
      tier   = 2
      custom = true
      why    = "Fires before connections are rejected rather than after."
      kql    = "P4Monitor_CL | summarize v=dcount(User_s) by Computer"
      op     = "GreaterThan"
      thresh = 0
    }
    proxy_cache_hit = {
      tier   = 2
      custom = true
      why    = "A falling hit rate means a remote site is pulling content across the WAN. It is usually reported as general slowness from a site with no local monitoring."
      kql    = "P4Proxy_CL | summarize v=avg(CacheHitRatio_d) by Computer"
      op     = "LessThan"
      thresh = 80
    }

    # ---- Tier 3: administrative, still causes outages --------------------
    license_expiry = {
      tier   = 3
      custom = true
      why    = "Licence expiry is a common and entirely preventable cause of downtime."
      kql    = "P4License_CL | summarize v=min(DaysRemaining_d)"
      op     = "LessThan"
      thresh = var.thresholds.license_expiry_days
    }
    depot_growth_projection = {
      tier   = 3
      custom = false
      why    = "Projected days-to-full gives enough lead time to add capacity during a planned window."
      kql    = "InsightsMetrics | where Name == 'FreeSpacePercentage' and Tags has 'p4depots' | summarize v=min(Val) by Computer"
      op     = "LessThan"
      thresh = var.thresholds.volume_free_pct_warn
    }
    restore_verify_stale = {
      tier   = 3
      custom = true
      why    = "If verification has not passed recently, the restore procedure is untested against current data."
      kql    = "P4RestoreVerify_CL | summarize v=datetime_diff('day', now(), max(TimeGenerated))"
      op     = "GreaterThan"
      thresh = var.thresholds.restore_verify_stale_days
    }
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "this" {
  # Alerts against custom tables are held back until those tables exist. An
  # alert that cannot resolve its table is worse than no alert: it looks like
  # coverage and can never fire.
  for_each = {
    for k, v in local.alerts : k => v
    if !v.custom || var.custom_log_tables_ready
  }
  name                 = "${var.name_prefix}-alert-${each.key}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  severity             = each.value.tier == 1 ? 1 : (each.value.tier == 2 ? 2 : 3)
  scopes               = [azurerm_log_analytics_workspace.this.id]
  evaluation_frequency = "PT5M"
  window_duration      = "PT15M"
  description          = each.value.why
  tags                 = var.tags

  criteria {
    query                   = each.value.kql
    time_aggregation_method = "Maximum"
    metric_measure_column   = "v"
    operator                = each.value.op
    threshold               = each.value.thresh
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.page.id]
  }
}
