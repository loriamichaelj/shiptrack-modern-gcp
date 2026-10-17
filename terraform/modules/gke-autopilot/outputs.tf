output "name" {
  description = "Name of the cluster. Credentials are fetched by name and region through the DNS endpoint."
  value       = google_container_cluster.this.name
}
