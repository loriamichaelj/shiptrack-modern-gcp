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

# Read by the cluster root, which grants each workload its access (ADR-0029). None of these is secret,
# and no workflow prints them.
output "topics" {
  description = "Pub/Sub topic names by flow."
  value       = module.pubsub.topics
}

output "subscriptions" {
  description = "Pub/Sub subscription names by flow."
  value       = module.pubsub.subscriptions
}

output "secret_ids" {
  description = "Secret IDs by account: app, migrator, and admin."
  value       = module.secrets.secret_ids
}

output "proof_of_delivery_bucket" {
  description = "Name of the proof-of-delivery bucket. Sensitive so that no run prints it."
  value       = module.proof_of_delivery_storage.bucket_name
  sensitive   = true
}

output "ui_ingress" {
  description = "Names the Gateway in deploy/gateway uses: the address, the certificate, and the Cloud Armor policy."
  value = {
    address         = module.ui_ingress.address_name
    certificate     = module.ui_ingress.certificate_name
    security_policy = module.ui_ingress.security_policy_name
  }
}
