output "notification_channel_id" {
  description = "ID of the notification channel that receives the alerts. Nothing here is secret, and no workflow prints it."
  value       = google_monitoring_notification_channel.alerts.id
}

output "alert_policies" {
  description = "Display names of the alert policies."
  value = sort(concat(
    [for p in google_monitoring_alert_policy.queue_age : p.display_name],
    [for p in google_monitoring_alert_policy.dead_letter : p.display_name],
    [for p in google_monitoring_alert_policy.burn : p.display_name],
    [google_monitoring_alert_policy.pod_restarts.display_name, google_monitoring_alert_policy.sla_scan_heartbeat.display_name],
  ))
}
