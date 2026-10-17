# The dataset the standard usage cost export writes to (ADR-0028). Terraform creates the dataset;
# switching the export on is a billing console step (terraform/seed/README.md). The plan account may
# read the dataset, for check-cost, and nothing else in it.

resource "google_bigquery_dataset" "billing_export" {
  #checkov:skip=CKV_GCP_81: Google-managed encryption is enough for cost rows, and a customer-managed key costs a key plus operations.
  project       = var.project_id
  dataset_id    = "shiptrack_billing_export"
  friendly_name = "ShipTrack billing export"
  description   = "Standard usage cost export for the ShipTrack project."
  location      = var.region
  labels        = local.labels

  # The cost history is the record the cost analysis is written from.
  delete_contents_on_destroy = false
}

resource "google_bigquery_dataset_iam_member" "plan_reads" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.billing_export.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:shiptrack-plan@${var.project_id}.iam.gserviceaccount.com"
}
