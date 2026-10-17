output "bucket_name" {
  description = "Name of the bucket. The workloads receive it as SHIPTRACK_PROOF_OF_DELIVERY_BUCKET."
  value       = google_storage_bucket.this.name
}
