# The database credentials (ADR-0010): one secret per account, each a JSON document with the shape of
# the AWS secret (username, password, host, port, dbname, engine) so the application reads them the
# same way. The passwords are ephemeral and written with a write-only argument, so no value is in
# state (ADR-0017).
#
# The application and migrator accounts are created inside the database by deploy-app's db-init Job,
# which reads these secrets and sets each role's password to the value stored here.

locals {
  accounts = {
    app      = { secret_id = "shiptrack-db-app", username = "shiptrack_app" }
    migrator = { secret_id = "shiptrack-db-migrator", username = "shiptrack_migrator" }
    admin    = { secret_id = "shiptrack-db-admin", username = var.admin_user }
  }
}

resource "google_secret_manager_secret" "this" {
  #checkov:skip=CKV_GCP_82: Google-managed encryption is enough for a dev database credential, and a customer-managed key costs a key plus operations.
  #checkov:skip=CKV2_GCP_18: Not a network; secrets have no firewall.
  for_each = local.accounts

  project   = var.project_id
  secret_id = each.value.secret_id
  labels    = var.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "this" {
  for_each = local.accounts

  secret                 = google_secret_manager_secret.this[each.key].id
  secret_data_wo_version = var.credentials_version
  secret_data_wo = jsonencode({
    username = each.value.username
    password = var.passwords[each.key]
    host     = var.host
    port     = 5432
    dbname   = var.dbname
    engine   = "postgres"
  })
}
