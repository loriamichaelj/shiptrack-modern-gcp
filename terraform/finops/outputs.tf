output "billing_export_dataset" {
  description = "ID of the dataset the cost export writes to. Nothing here is secret, and no workflow prints it."
  value       = google_bigquery_dataset.billing_export.dataset_id
}
