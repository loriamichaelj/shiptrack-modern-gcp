# The proof-of-delivery bucket (ADR-0011, ADR-0023): Standard class, uniform access, public access
# prevention enforced, versioning off. Objects live under proof-of-delivery/{shipment}/{document}.
#
# Downloads are signed URLs, signed through the IAM signing API as the account
# shiptrack-proof-of-delivery, which can only read this bucket. The api's own access (upload, and
# permission to sign as that account) is granted with the cluster (ADR-0029).

# A bucket name is global and a deleted name is not reliably free, so the name carries a suffix.
resource "random_id" "bucket" {
  byte_length = 4
}

resource "google_storage_bucket" "this" {
  #checkov:skip=CKV_GCP_62: Access logs would be a second bucket to pay for and secure; Admin Activity audit logs stay on.
  #checkov:skip=CKV_GCP_78: Versioning is off (design 8.2); a rewritten document is not recoverable, and the cost of old versions is not worth it for a dev demonstration.
  project                     = var.project_id
  name                        = "shiptrack-proof-of-delivery-${random_id.bucket.hex}"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = !var.protection
  labels                      = var.labels

  versioning {
    enabled = false
  }
}

# The signer reads and nothing else.
resource "google_storage_bucket_iam_member" "signer_reads" {
  bucket = google_storage_bucket.this.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:shiptrack-proof-of-delivery@${var.project_id}.iam.gserviceaccount.com"
}
