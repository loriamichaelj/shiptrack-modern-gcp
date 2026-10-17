output "secret_ids" {
  description = "Secret IDs by account: app, migrator, and admin."
  value       = { for account, secret in google_secret_manager_secret.this : account => secret.secret_id }
}
