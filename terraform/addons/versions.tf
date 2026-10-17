terraform {
  required_version = ">= 1.11"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.7.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.3.0"
    }
  }
}

# The backend block is written to backend.tf by .github/scripts/terraform-ci.sh.

provider "google" {
  project = var.project_id
  region  = var.region
}

# The cluster is reached through its DNS endpoint with the apply account's short-lived token. The IP
# endpoint is off (ADR-0007), and the DNS endpoint's certificate is publicly trusted, so no CA is needed.
provider "kubernetes" {
  host  = "https://${data.google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint}"
  token = data.google_client_config.this.access_token
}
