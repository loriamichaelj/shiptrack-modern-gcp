# Permissions: what each service account may do.
#
# No account here can change project-level IAM or create service accounts. The apply account
# administers services (network, cluster, database, queues, secrets, buckets, monitoring), and
# grants on those resources are made by the service's own admin role, never on the project.

locals {
  project_roles = {
    plan = [
      "roles/viewer",
      "roles/iam.securityReviewer", # reads IAM policies, which viewer does not
      "roles/serviceusage.serviceUsageConsumer",
    ]
    apply = [
      "roles/cloudsql.admin",
      "roles/compute.networkAdmin",
      "roles/container.admin",
      "roles/logging.configWriter",
      "roles/monitoring.editor",
      "roles/pubsub.admin",
      "roles/secretmanager.admin",
      "roles/servicenetworking.networksAdmin",
      "roles/serviceusage.serviceUsageConsumer",
      "roles/storage.admin",
    ]
    deploy = [
      "roles/container.clusterViewer", # fetches credentials; every cluster permission is Kubernetes RBAC
      "roles/serviceusage.serviceUsageConsumer",
    ]
    gke-node = [
      "roles/container.defaultNodeServiceAccount",
    ]
  }

  project_bindings = merge([
    for account, roles in local.project_roles : {
      for role in roles : "${account}/${role}" => { account = account, role = role }
    }
  ]...)
}

resource "google_project_iam_member" "this" {
  for_each = local.project_bindings

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.this[each.value.account].email}"
}

# State bucket. Plans read the state and never lock it (-lock=false); applies write it and its lock.
resource "google_storage_bucket_iam_member" "state_plan" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.this["plan"].email}"
}

resource "google_storage_bucket_iam_member" "state_apply" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.this["apply"].email}"
}

# The apply account attaches the node identity to the cluster, and manages who may use the signer.
resource "google_service_account_iam_member" "apply_uses_gke_node" {
  service_account_id = google_service_account.this["gke-node"].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.this["apply"].email}"
}

resource "google_service_account_iam_member" "apply_administers_proof_of_delivery" {
  service_account_id = google_service_account.this["proof-of-delivery"].name
  role               = "roles/iam.serviceAccountAdmin"
  member             = "serviceAccount:${google_service_account.this["apply"].email}"
}
