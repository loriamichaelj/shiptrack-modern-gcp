# Names the cluster and the database use. The other roots look the resources up by these names
# (data sources), so no root reads another's state. Nothing here is secret, and no workflow prints it.

output "network_name" {
  description = "Name of the VPC."
  value       = module.network.network_name
}

output "subnet_name" {
  description = "Name of the subnet."
  value       = module.network.subnet_name
}

output "pods_range_name" {
  description = "Name of the subnet's secondary range for pods."
  value       = module.network.pods_range_name
}

output "services_range_name" {
  description = "Name of the subnet's secondary range for services."
  value       = module.network.services_range_name
}

output "private_services_range_name" {
  description = "Name of the range reserved for Cloud SQL."
  value       = module.network.private_services_range_name
}
