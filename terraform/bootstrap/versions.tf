terraform {
  required_version = ">= 1.11"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.7.0"
    }
  }
}

# The backend block is written to backend.tf by scripts/ci.sh once the state bucket exists.

provider "google" {
  project = var.project_id
  region  = var.region
}
