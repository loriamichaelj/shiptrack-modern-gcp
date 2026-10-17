# Trust relationships: which GitHub jobs may act as which service account.
#
# A job presents a GitHub OIDC token. The Workload Identity provider (created by hand) accepts it
# only from this repository, maps its sub claim to the subject, and each binding below lets one
# exact subject impersonate one service account. A subject names the environment or the event, so
# a job outside the approved environment cannot become apply or deploy. The environment's
# deployment-branch rule (dev only) is what keeps a workflow on another branch out.

locals {
  trusted_subjects = {
    "plan/pull-request" = {
      account = "plan"
      subject = "${local.subject_prefix}:pull_request"
    }
    "plan/dev-branch" = {
      account = "plan"
      subject = "${local.subject_prefix}:ref:refs/heads/dev"
    }
    "apply/dev" = {
      account = "apply"
      subject = "${local.subject_prefix}:environment:dev"
    }
    "deploy/dev" = {
      account = "deploy"
      subject = "${local.subject_prefix}:environment:dev"
    }
  }
}

resource "google_service_account_iam_member" "github" {
  for_each = local.trusted_subjects

  service_account_id = google_service_account.this[each.value.account].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${local.pool}/subject/${each.value.subject}"
}
