# What the data root created, by name. The root reads that root's state, which the plan and apply
# accounts can both read.
data "terraform_remote_state" "data" {
  backend = "gcs"

  config = {
    bucket = "shiptrack-tfstate-${var.project_number}"
    prefix = "gcp/data"
  }
}

module "gke_autopilot" {
  source = "../modules/gke-autopilot"

  project_id           = var.project_id
  region               = var.region
  network              = "projects/${var.project_id}/global/networks/${data.terraform_remote_state.data.outputs.network_name}"
  subnetwork           = "projects/${var.project_id}/regions/${var.region}/subnetworks/${data.terraform_remote_state.data.outputs.subnet_name}"
  pods_range_name      = data.terraform_remote_state.data.outputs.pods_range_name
  services_range_name  = data.terraform_remote_state.data.outputs.services_range_name
  node_service_account = "shiptrack-gke-node@${var.project_id}.iam.gserviceaccount.com"
  labels               = local.labels
  deletion_protection  = var.deletion_protection
}

# One call per workload (design 7.3), after the cluster, because its workload identity pool is created
# with the first cluster (ADR-0029). The Kubernetes service accounts are those of the chart.
module "workload_access" {
  source   = "../modules/workload-access"
  for_each = local.workloads

  project_id                 = var.project_id
  project_number             = var.project_number
  namespace                  = var.namespace
  kubernetes_service_account = "shiptrack-${each.key}"
  topics_publisher           = toset(each.value.topics_publisher)
  subscriptions_subscriber   = toset(each.value.subscriptions_subscriber)
  secrets_accessor           = toset(each.value.secrets_accessor)
  bucket_object_user         = each.value.bucket_object_user
  bucket_name                = data.terraform_remote_state.data.outputs.proof_of_delivery_bucket
  may_sign_as                = each.value.may_sign_as

  depends_on = [module.gke_autopilot]
}
