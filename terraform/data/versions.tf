terraform {
  required_version = ">= 1.11"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
  }
}

# The backend block is written to backend.tf by .github/scripts/terraform-ci.sh.

provider "google" {
  project = var.project_id
  region  = var.region
}
