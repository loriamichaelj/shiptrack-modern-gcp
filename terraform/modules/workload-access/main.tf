# One workload's access (ADR-0010, design 7.3). The workload is a Kubernetes service account, and its
# IAM principal sits in the project's workload identity pool, so it holds no key and no Google service
# account. Each role is granted on the single resource the workload uses, never on the project.
#
# The pool exists once the cluster does, so the cluster root calls this after the cluster (ADR-0029).

locals {
  principal = "principal://iam.googleapis.com/projects/${var.project_number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/${var.namespace}/sa/${var.kubernetes_service_account}"
}

resource "google_pubsub_topic_iam_member" "publisher" {
  for_each = var.topics_publisher

  project = var.project_id
  topic   = each.value
  role    = "roles/pubsub.publisher"
  member  = local.principal
}

resource "google_pubsub_subscription_iam_member" "subscriber" {
  for_each = var.subscriptions_subscriber

  project      = var.project_id
  subscription = each.value
  role         = "roles/pubsub.subscriber"
  member       = local.principal
}

resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = var.secrets_accessor

  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = local.principal
}

resource "google_storage_bucket_iam_member" "object_user" {
  count = var.bucket_object_user ? 1 : 0

  bucket = var.bucket_name
  role   = "roles/storage.objectUser"
  member = local.principal
}

# Signing a download URL asks the IAM signing API to sign as the proof-of-delivery signer, which can
# only read the bucket. The role is granted on that one account.
resource "google_service_account_iam_member" "token_creator" {
  count = var.may_sign_as == null ? 0 : 1

  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.may_sign_as}"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = local.principal
}
