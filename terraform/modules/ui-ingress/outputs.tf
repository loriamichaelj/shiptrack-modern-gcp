output "address_name" {
  description = "Name of the reserved address. The Gateway names it."
  value       = google_compute_address.ui.name
}

output "security_policy_name" {
  description = "Name of the Cloud Armor policy. The backend policy names it."
  value       = google_compute_region_security_policy.ui.name
}

output "proxy_only_cidr" {
  description = "Range of the proxy-only subnet. The network policy that admits the load balancer names it."
  value       = google_compute_subnetwork.proxy_only.ip_cidr_range
}
