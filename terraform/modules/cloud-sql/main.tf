# Cloud SQL for PostgreSQL (ADR-0008): a shared-core instance with a private address only, TLS
# required, daily backups kept 7 days, and no point-in-time recovery. The application's roles and
# grants are created by deploy-app's db-init Job, not here.

# A deleted instance's name cannot be reused for a while, so the name carries a suffix (ADR-0027).
resource "random_id" "instance" {
  byte_length = 3
}

resource "google_sql_database_instance" "this" {
  #checkov:skip=CKV_GCP_6: ssl_mode = ENCRYPTED_ONLY below requires TLS; the check reads the older require_ssl argument.
  #checkov:skip=CKV_GCP_79: PostgreSQL 17 is the version the application's tests run against (ADR-0008).
  #checkov:skip=CKV_GCP_108: Hostname logging adds a reverse lookup to every connection and nothing here needs it.
  #checkov:skip=CKV_GCP_109: Log level is left at the default; the connection and lock flags below are the useful ones.
  #checkov:skip=CKV_GCP_110: pgAudit and statement logging write query text, which can include data, into logs that cost money.
  #checkov:skip=CKV_GCP_111: Statement logging can write data into the logs, and a dev database has no auditor to read them.
  #checkov:skip=CKV2_GCP_13: Logging every statement's duration adds volume for a database that is rarely queried.
  project             = var.project_id
  name                = "shiptrack-${random_id.instance.hex}"
  region              = var.region
  database_version    = "POSTGRES_17"
  deletion_protection = var.deletion_protection

  settings {
    tier                        = var.tier
    edition                     = "ENTERPRISE"
    availability_type           = "ZONAL"
    disk_size                   = var.disk_size_gb
    disk_type                   = "PD_SSD"
    deletion_protection_enabled = var.deletion_protection
    user_labels                 = var.labels

    # Connection, checkpoint, and lock-wait logging: a few lines per event, inside the free allotment.
    database_flags {
      name  = "log_connections"
      value = "on"
    }

    database_flags {
      name  = "log_disconnections"
      value = "on"
    }

    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }

    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = false

      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }
  }

  depends_on = [var.private_services_connection]
}

resource "google_sql_database" "shiptrack" {
  project  = var.project_id
  name     = "shiptrack"
  instance = google_sql_database_instance.this.name
}

# The administrator, a member of cloudsqlsuperuser. The password is write-only: Terraform sends it
# and keeps neither it nor a hash.
resource "google_sql_user" "admin" {
  project             = var.project_id
  instance            = google_sql_database_instance.this.name
  name                = var.admin_user
  password_wo         = var.admin_password
  password_wo_version = var.admin_password_version
}
