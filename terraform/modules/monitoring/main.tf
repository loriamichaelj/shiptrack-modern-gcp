# Alerting and the dashboard for the workloads (ADR-0014, ADR-0032). Everything is Cloud Monitoring: no pods.
#
# The queue and pod alerts read Google's own metrics. The availability alerts read the application's
# Prometheus metrics, which Managed Service for Prometheus collects through the chart's PodMonitoring.
# The SLA heartbeat reads a counter made from the log record `sla_scan_completed`.

locals {
  # Each alert's documentation names the runbook that explains the response (docs/runbooks).
  runbook = "Runbook: docs/runbooks/"

  # The error budget the burn rates multiply: 0.5% for a 99.5% target.
  error_budget = 1 - var.availability_target
}

resource "google_monitoring_notification_channel" "alerts" {
  project      = var.project_id
  display_name = "ShipTrack alerts"
  type         = "email"
  labels       = { email_address = var.alert_email }
  user_labels  = var.labels
}

# The scan runs every five minutes (the chart's slaScan schedule) and logs this record each time. The
# log-based metric counts those records so that an alert can notice when they stop.
resource "google_logging_metric" "sla_scan_completed" {
  project     = var.project_id
  name        = "shiptrack_sla_scan_completed"
  description = "Completed runs of the SLA scan, counted from the log record sla_scan_completed."
  filter      = <<-EOT
    resource.type="k8s_container"
    resource.labels.namespace_name="${var.namespace}"
    jsonPayload.event="sla_scan_completed"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}
