# Database passwords. They are ephemeral: generated for one run, handed to write-only arguments, and
# never stored in state, a plan, or a log (ADR-0017). Raise db_credentials_version to replace them.

ephemeral "random_password" "db" {
  for_each = toset(["admin", "app", "migrator"])

  length  = 32
  special = false
}
