# One dashboard: request rate, errors, latency, queue depth and age, pod restarts, database connections.
# Application series are PromQL over Managed Prometheus; queue and pod series are Google's own metrics.

locals {
  prometheus_tiles = [
    { title = "Requests per second, by status class", query = "sum by (status_class) (rate(http_requests_total[5m]))" },
    { title = "Server error ratio", query = "sum(rate(http_requests_total{status_class=\"5xx\"}[5m])) / sum(rate(http_requests_total[5m]))" },
    { title = "Request latency, 95th percentile (seconds)", query = "histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))" },
    { title = "Event apply lag, 95th percentile (seconds)", query = "histogram_quantile(0.95, sum by (le) (rate(shiptrack_event_apply_lag_seconds_bucket[5m])))" },
    { title = "Events processed per second, by result", query = "sum by (result) (rate(shiptrack_events_processed_total[5m]))" },
    { title = "Database connections in use", query = "sum(shiptrack_db_pool_checked_out)" },
  ]

  # The metric filters of the Google-metric tiles. The dead-letter subscriptions are in the same charts.
  google_tiles = [
    {
      title      = "Messages waiting, by subscription"
      metric     = "pubsub.googleapis.com/subscription/num_undelivered_messages"
      resource   = "pubsub_subscription"
      group      = "resource.label.subscription_id"
      aligner    = "ALIGN_MAX"
      filter_ext = ""
    },
    {
      title      = "Age of the oldest waiting message (seconds), by subscription"
      metric     = "pubsub.googleapis.com/subscription/oldest_unacked_message_age"
      resource   = "pubsub_subscription"
      group      = "resource.label.subscription_id"
      aligner    = "ALIGN_MAX"
      filter_ext = ""
    },
    {
      title      = "Container restarts, by workload"
      metric     = "kubernetes.io/container/restart_count"
      resource   = "k8s_container"
      group      = "resource.label.container_name"
      aligner    = "ALIGN_DELTA"
      filter_ext = " AND resource.label.namespace_name=\"${var.namespace}\""
    },
  ]

  tiles = concat(
    [for t in local.prometheus_tiles : {
      title = t.title
      xyChart = {
        dataSets = [{
          plotType        = "LINE"
          timeSeriesQuery = { prometheusQuery = t.query }
        }]
      }
    }],
    [for t in local.google_tiles : {
      title = t.title
      xyChart = {
        dataSets = [{
          plotType = "LINE"
          timeSeriesQuery = {
            timeSeriesFilter = {
              filter = "metric.type=\"${t.metric}\" AND resource.type=\"${t.resource}\"${t.filter_ext}"
              aggregation = {
                alignmentPeriod    = "60s"
                perSeriesAligner   = t.aligner
                crossSeriesReducer = "REDUCE_MAX"
                groupByFields      = [t.group]
              }
            }
          }
        }]
      }
    }],
  )

  # Three tiles to a row, each a third of the 12-column grid.
  mosaic_tiles = [for i, t in local.tiles : {
    xPos   = (i % 3) * 4
    yPos   = floor(i / 3) * 4
    width  = 4
    height = 4
    widget = t
  }]
}

resource "google_monitoring_dashboard" "shiptrack" {
  project = var.project_id

  dashboard_json = jsonencode({
    displayName = "shiptrack"
    labels      = var.labels
    mosaicLayout = {
      columns = 12
      tiles   = local.mosaic_tiles
    }
  })
}
