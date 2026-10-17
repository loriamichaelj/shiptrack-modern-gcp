# Every service account the pipelines and the cluster use. They are created here, once, so that the
# apply account never needs to create service accounts or grant itself roles.
#
#   plan                pull requests: reads the project and the state
#   apply               Terraform applies for data, cluster, and addons (environment dev)
#   deploy              Helm deploys and the contract run (environment dev)
#   gke-node            identity of the GKE nodes
#   proof-of-delivery   signs proof-of-delivery download URLs; may only read that bucket

locals {
  service_accounts = {
    plan              = "ShipTrack Terraform plan (pull requests, read-only)"
    apply             = "ShipTrack Terraform apply (environment dev)"
    deploy            = "ShipTrack Helm deploy (environment dev)"
    gke-node          = "ShipTrack GKE node identity"
    proof-of-delivery = "ShipTrack proof-of-delivery URL signer (read-only)"
  }
}

resource "google_service_account" "this" {
  for_each = local.service_accounts

  project      = var.project_id
  account_id   = "shiptrack-${each.key}"
  display_name = each.value

  depends_on = [google_project_service.this]
}
