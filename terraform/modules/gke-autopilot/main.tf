# GKE Autopilot (ADR-0005, design 8.3): private nodes that reach what they need through Cloud NAT
# (ADR-0007), the control plane reached only through its DNS endpoint with IAM as the gate and no
# IP endpoint, Workload Identity, managed Prometheus, and the regular release channel. Workloads run on
# Spot pods; a pod asks for that with a node selector, so nothing about it is set here.

# The IP endpoint is off, so master authorized networks have nothing to restrict (ADR-0007).
#trivy:ignore:AVD-GCP-0061
resource "google_container_cluster" "this" {
  #checkov:skip=CKV_GCP_12: Autopilot's dataplane enforces network policy and does not take the older network_policy block; the chart ships the policies (design 7.4).
  #checkov:skip=CKV_GCP_20: The IP endpoint is off, so there is no address to restrict; the DNS endpoint is gated by IAM (ADR-0007).
  #checkov:skip=CKV_GCP_61: Flow logs and intranode visibility cost money for a dev environment, and Autopilot's dataplane keeps its own metrics.
  #checkov:skip=CKV_GCP_65: Group-based RBAC needs a Google Workspace group, which this project does not have; access is by account.
  #checkov:skip=CKV_GCP_66: Binary Authorization needs an attestor and a signing pipeline that this dev environment does not have; images are deployed by digest instead.
  #checkov:skip=CKV_GCP_69: Autopilot runs the GKE metadata server on every node, with Workload Identity; it is not a setting.
  project             = var.project_id
  name                = "shiptrack"
  location            = var.region
  enable_autopilot    = true
  deletion_protection = var.deletion_protection
  resource_labels     = var.labels

  network    = var.network
  subnetwork = var.subnetwork

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes = true
  }

  # The IP endpoint is off, so there is no address to allow-list or to leak. The DNS endpoint is reached
  # from any network and authorizes with IAM.
  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = true
    }

    ip_endpoints_config {
      enabled = false
    }
  }

  # Autopilot's default, written out: the dataplane that enforces network policy.
  datapath_provider = "ADVANCED_DATAPATH"

  # No client certificates: access is through IAM.
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = var.node_service_account
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]

    managed_prometheus {
      enabled = true
    }
  }

  # Splits the bill by namespace and workload label in the billing export (ADR-0028).
  cost_management_config {
    enabled = true
  }
}
