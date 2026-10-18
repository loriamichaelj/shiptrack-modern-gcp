locals {
  # One entry per Pub/Sub alert. Age is in seconds; the dead-letter alert fires on any message.
  queue_age = {
    "events-queue-age" = {
      title     = "Events queue is falling behind"
      threshold = 120
      severity  = "ERROR"
      sev       = "SEV2"
    }
    "events-queue-age-critical" = {
      title     = "Events queue is far behind"
      threshold = 600
      severity  = "CRITICAL"
      sev       = "SEV1"
    }
  }

  dead_letters = {
    "events-dlq-visible" = { flow = "events", title = "Events are in the dead-letter queue" }
    "notify-dlq-visible" = { flow = "notifications", title = "Notifications are in the dead-letter queue" }
  }
}

resource "google_monitoring_alert_policy" "queue_age" {
  for_each = local.queue_age

  project      = var.project_id
  display_name = "shiptrack ${each.key}"
  combiner     = "OR"
  severity     = each.value.severity
  user_labels  = merge(var.labels, { severity = lower(each.value.sev) })

  documentation {
    mime_type = "text/markdown"
    content   = "${each.value.sev}: the oldest unacknowledged event has waited more than ${each.value.threshold} seconds for five minutes. The workers are down, stuck, or too slow.\n\n${local.runbook}event-backlog.md"
  }

  conditions {
    display_name = each.value.title
    condition_threshold {
      filter          = "metric.type=\"pubsub.googleapis.com/subscription/oldest_unacked_message_age\" AND resource.type=\"pubsub_subscription\" AND resource.label.subscription_id=\"${var.subscriptions["events"]}\""
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold
      duration        = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.alerts.id]
}

resource "google_monitoring_alert_policy" "dead_letter" {
  for_each = local.dead_letters

  project      = var.project_id
  display_name = "shiptrack ${each.key}"
  combiner     = "OR"
  severity     = "ERROR"
  user_labels  = merge(var.labels, { severity = "sev2" })

  documentation {
    mime_type = "text/markdown"
    content   = "SEV2: a message failed five deliveries and is waiting in the ${each.value.flow} dead-letter subscription.\n\n${local.runbook}dead-letter-redrive.md"
  }

  conditions {
    display_name = each.value.title
    condition_threshold {
      filter          = "metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\" AND resource.type=\"pubsub_subscription\" AND resource.label.subscription_id=\"${var.dead_letter_subscriptions[each.value.flow]}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.alerts.id]
}

resource "google_monitoring_alert_policy" "pod_restarts" {
  project      = var.project_id
  display_name = "shiptrack pod-restarts"
  combiner     = "OR"
  severity     = "ERROR"
  user_labels  = merge(var.labels, { severity = "sev2" })

  documentation {
    mime_type = "text/markdown"
    content   = "SEV2: a container in the ${var.namespace} namespace restarted more than three times in ten minutes.\n\n${local.runbook}pod-restarts.md"
  }

  conditions {
    display_name = "A container keeps restarting"
    condition_threshold {
      filter          = "metric.type=\"kubernetes.io/container/restart_count\" AND resource.type=\"k8s_container\" AND resource.label.namespace_name=\"${var.namespace}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 3
      duration        = "0s"

      aggregations {
        alignment_period   = "600s"
        per_series_aligner = "ALIGN_DELTA"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.alerts.id]
}

# Absent means no completed scan for fifteen minutes, which is three missed runs.
resource "google_monitoring_alert_policy" "sla_scan_heartbeat" {
  project      = var.project_id
  display_name = "shiptrack sla-scan-heartbeat"
  combiner     = "OR"
  severity     = "ERROR"
  user_labels  = merge(var.labels, { severity = "sev2" })

  documentation {
    mime_type = "text/markdown"
    content   = "SEV2: no SLA scan has completed for fifteen minutes. Overdue shipments are not being flagged.\n\n${local.runbook}sla-scan-stopped.md"
  }

  conditions {
    display_name = "The SLA scan stopped"
    condition_absent {
      filter   = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.sla_scan_completed.name}\" AND resource.type=\"k8s_container\""
      duration = "900s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.alerts.id]
}

# Burn rate is the error ratio divided by the error budget. Both windows must exceed the multiple, so a
# short spike that is already over does not page. When there is no traffic the ratio has no value and
# nothing fires. Whether Cloud Monitoring accepts these PromQL policies is proven by the first apply [VERIFY].
locals {
  burn = {
    "slo-availability-fast-burn" = {
      title    = "Availability budget is burning fast"
      multiple = 14.4
      long     = "1h"
      short    = "5m"
      severity = "CRITICAL"
      sev      = "SEV1"
    }
    "slo-availability-slow-burn" = {
      title    = "Availability budget is burning slowly"
      multiple = 6
      long     = "6h"
      short    = "30m"
      severity = "ERROR"
      sev      = "SEV2"
    }
  }
}

resource "google_monitoring_alert_policy" "burn" {
  for_each = local.burn

  project      = var.project_id
  display_name = "shiptrack ${each.key}"
  combiner     = "OR"
  severity     = each.value.severity
  user_labels  = merge(var.labels, { severity = lower(each.value.sev) })

  documentation {
    mime_type = "text/markdown"
    content   = "${each.value.sev}: server errors are using the ${format("%.1f", local.error_budget * 100)}% error budget ${each.value.multiple} times faster than the objective allows, over ${each.value.long} and ${each.value.short}.\n\n${local.runbook}availability-burn.md"
  }

  conditions {
    display_name = each.value.title
    condition_prometheus_query_language {
      query               = <<-EOT
        (
          sum(rate(http_requests_total{status_class="5xx"}[${each.value.long}])) / sum(rate(http_requests_total[${each.value.long}]))
          > ${format("%.5f", each.value.multiple * local.error_budget)}
        )
        and
        (
          sum(rate(http_requests_total{status_class="5xx"}[${each.value.short}])) / sum(rate(http_requests_total[${each.value.short}]))
          > ${format("%.5f", each.value.multiple * local.error_budget)}
        )
      EOT
      duration            = "0s"
      evaluation_interval = "60s"
      alert_rule          = replace(each.key, "-", "_")
    }
  }

  notification_channels = [google_monitoring_notification_channel.alerts.id]
}
