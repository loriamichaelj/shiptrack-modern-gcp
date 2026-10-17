locals {
  labels = {
    environment = "dev"
    name        = "shiptrack"
  }

  # Fixed by the project number so the name is unique without a random suffix. scripts/ci.sh
  # derives the same name.
  state_bucket_name = "shiptrack-tfstate-${var.project_number}"

  pool = "projects/${var.project_number}/locations/global/workloadIdentityPools/${var.workload_identity_pool_id}"

  # The repository issues OIDC tokens with an immutable subject:
  # repo:<owner>@<owner id>/<repo>@<repo id>:<suffix>.
  subject_prefix = "repo:${var.github_org}@${var.github_owner_id}/${var.github_repo}@${var.github_repository_id}"
}
