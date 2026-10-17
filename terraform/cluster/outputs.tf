output "cluster_name" {
  description = "Name of the cluster. Credentials are fetched by name and region through the DNS endpoint. Nothing here is secret, and the cluster's endpoint is deliberately not an output."
  value       = module.gke_autopilot.name
}
