output "network_name" {
  description = "Name of the VPC."
  value       = google_compute_network.this.name
}

output "network_id" {
  description = "ID of the VPC."
  value       = google_compute_network.this.id
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

output "private_services_connection" {
  description = "ID of the private services access peering. A resource that needs the peering depends on this."
  value       = google_service_networking_connection.private_services.id
}
