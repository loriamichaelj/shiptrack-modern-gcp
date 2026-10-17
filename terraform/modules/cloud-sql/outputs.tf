output "instance_name" {
  description = "Name of the instance."
  value       = google_sql_database_instance.this.name
}

output "private_ip_address" {
  description = "The instance's private address. It goes into the credentials secrets."
  value       = google_sql_database_instance.this.private_ip_address
}

output "database_name" {
  description = "Name of the application database."
  value       = google_sql_database.shiptrack.name
}

output "admin_user" {
  description = "Name of the administrator."
  value       = google_sql_user.admin.name
}
