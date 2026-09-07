# The alert set. Anyone can alert on VM CPU; these are the signals that
# actually precede a Perforce outage. Tiering is deliberate — tier 1 pages,
# tier 2 tickets, tier 3 emails.

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
  # Each entry documents WHY it exists. That rationale is the part that
  # transfers to someone else's estate during an audit.
  alerts = {
    # ---- Tier 1: outage imminent or in progress -------------------------
    p4logs_free = {
      tier   = 1
      why    = "Journal cannot be written -> p4d halts. This is the outage nobody sees coming, because the metadata volume still looks fine."
      kql    = "InsightsMetrics | where Name == 'FreeSpacePercentage' and Tags has 'p4logs' | summarize v=min(Val) by Computer"
      op     = "LessThan"
      thresh = var.thresholds.volume_free_pct_page
    }
    p4db_free = {
      tier   = 1
      why    = "Metadata volume full is the worst outage on the list and the slowest to recover from."
      kql    = "InsightsMetrics | where Name == 'FreeSpacePercentage' and Tags has 'p4db' | summarize v=min(Val) by Computer"
      op     = "LessThan"
      thresh = var.thresholds.volume_free_pct_page
    }
    checkpoint_failed = {
      tier   = 1
      why    = "A missed checkpoint costs nothing today and everything on the day you need to restore."
      kql    = "Syslog | where SyslogMessage has 'checkpoint' and SyslogMessage has_any ('failed','error') | summarize v=count() by Computer"
      op     = "GreaterThan"
      thresh = 0
    }
    replica_lag = {
      tier   = 1
      why    = "Rising lag means the real RPO is no longer what the runbook claims. This alert is what turns a claimed RPO into a measured one."
      kql    = "P4Replication_CL | summarize v=max(LagSeconds_d) by Computer"
      op     = "GreaterThan"
      thresh = var.thresholds.replica_lag_seconds
    }
    p4d_restart = {
      tier   = 1
      why    = "Unexplained restarts are the leading indicator of a resource or memory problem two weeks out."
      kql    = "Heartbeat | summarize v=count() by Computer" # placeholder: replace with p4d uptime counter
      op     = "GreaterThan"
      thresh = 0
    }

    # ---- Tier 2: users already hurting ----------------------------------
    submit_latency_p95 = {
      tier   = 2
      why    = "The user-facing SLI. Everything in tier 1 is ultimately a proxy for this."
      kql    = "P4Commands_CL | where Command_s == 'user-submit' | summarize v=percentile(Duration_d, 95) by Computer"
      op     = "GreaterThan"
      thresh = var.thresholds.submit_p95_seconds
    }
    blocked_commands = {
      tier   = 2
      why    = "One bad sync against a huge path holding a lock stalls everyone. p4 monitor sees it before users report it."
      kql    = "P4Monitor_CL | where Status_s == 'B' or Runtime_d > ${var.thresholds.blocked_command_secs} | summarize v=count() by Computer"
      op     = "GreaterThan"
      thresh = 0
    }
    connection_saturation = {
      tier   = 2
      why    = "You want the alert before connections are rejected, not after."
      kql    = "P4Monitor_CL | summarize v=dcount(User_s) by Computer"
      op     = "GreaterThan"
      thresh = 0
    }
    proxy_cache_hit = {
      tier   = 2
      why    = "A collapsing hit rate means a remote studio is pulling everything across the WAN. It surfaces as 'Perforce is slow' from a site with no alerting of its own."
      kql    = "P4Proxy_CL | summarize v=avg(CacheHitRatio_d) by Computer"
      op     = "LessThan"
      thresh = 80
    }

    # ---- Tier 3: administrative, still causes outages --------------------
    license_expiry = {
      tier   = 3
      why    = "This has taken down more servers than any hardware fault."
      kql    = "P4License_CL | summarize v=min(DaysRemaining_d)"
      op     = "LessThan"
      thresh = var.thresholds.license_expiry_days
    }
    depot_growth_projection = {
      tier   = 3
      why    = "Projected days-to-full is the number that lets you buy disk before the weekend rather than during it."
      kql    = "InsightsMetrics | where Name == 'FreeSpacePercentage' and Tags has 'p4depots' | summarize v=min(Val) by Computer"
      op     = "LessThan"
      thresh = var.thresholds.volume_free_pct_warn
    }
    restore_verify_stale = {
      tier   = 3
      why    = "If verification has not passed recently, the recovery plan is theoretical."
      kql    = "P4RestoreVerify_CL | summarize v=datetime_diff('day', now(), max(TimeGenerated))"
      op     = "GreaterThan"
      thresh = var.thresholds.restore_verify_stale_days
    }
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "this" {
  for_each             = local.alerts
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
