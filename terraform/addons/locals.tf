locals {
  labels = {
    environment = "dev"
    name        = "shiptrack"
  }

  # The Kubernetes user the deploy account appears as: GKE authorizes an IAM account by its email.
  deploy_user = "shiptrack-deploy@${var.project_id}.iam.gserviceaccount.com"
}
