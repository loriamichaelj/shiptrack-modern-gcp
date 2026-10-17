# Names the cluster and the database use. The other roots look the resources up by these names
# (data sources), so no root reads another's state. Nothing here is secret, and no workflow prints it.

output "network_name" {
  description = "Name of the VPC."
  value       = google_compute_network.this.name
}

output "subnet_name" {
  description = "Name of the subnet."
  value       = google_compute_subnetwork.this.name
}

output "pods_range_name" {
  description = "Name of the subnet's secondary range for pods."
  value       = "pods"
}

output "services_range_name" {
  description = "Name of the subnet's secondary range for services."
  value       = "services"
}

output "private_services_range_name" {
  description = "Name of the range reserved for Cloud SQL."
  value       = google_compute_global_address.private_services.name
}
