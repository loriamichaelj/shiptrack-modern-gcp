terraform {
  required_version = ">= 1.11"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.7.0"
    }
  }
}

# The backend block is written to backend.tf by .github/scripts/terraform-ci.sh.

# The Billing Budget API charges its quota to a project, so the budget is created with the project's
# quota and not the caller's.
provider "google" {
  project               = var.project_id
  region                = var.region
  billing_project       = var.project_id
  user_project_override = true
}
