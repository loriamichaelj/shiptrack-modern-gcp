# The Terraform state bucket. On the first run, scripts/ci.sh creates only this bucket (-target)
# with local state and moves the state into it before anything else is created.

resource "google_storage_bucket" "state" {
  #checkov:skip=CKV_GCP_62: Usage logging needs a second bucket to protect; this one holds a few state files for three accounts, and Admin Activity audit logs record changes to it (design §12)
  name          = local.state_bucket_name
  project       = var.project_id
  location      = var.region
  storage_class = "STANDARD"
  labels        = local.labels

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  # Old state versions are recovery points, not an archive: keep the newest ten.
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      with_state         = "ARCHIVED"
      num_newer_versions = 10
    }
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.this["storage.googleapis.com"]]
}
