output "address_name" {
  description = "Name of the reserved address. The Gateway names it."
  value       = google_compute_global_address.ui.name
}

output "certificate_name" {
  description = "Name of the managed certificate. The Gateway names it."
  value       = google_compute_managed_ssl_certificate.ui.name
}

output "security_policy_name" {
  description = "Name of the Cloud Armor policy. The backend policy names it."
  value       = google_compute_security_policy.ui.name
}
