# The network (ADR-0007): private nodes, one NAT gateway for what they pull and call, Private Google
# Access for Google's own APIs, and a range reserved for Cloud SQL's private address. None of these
# resources takes labels; the project carries the environment and name tags.

resource "google_compute_network" "this" {
  #checkov:skip=CKV2_GCP_18: Ingress is denied by the implied rule, and GKE adds the few rules the cluster needs.
  project                 = var.project_id
  name                    = "shiptrack"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "this" {
  #checkov:skip=CKV_GCP_26: Flow logs are off for cost; the project keeps Admin Activity audit logs.
  project                  = var.project_id
  name                     = "shiptrack-${var.region}"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

resource "google_compute_router" "this" {
  project = var.project_id
  name    = "shiptrack"
  region  = var.region
  network = google_compute_network.this.id
}

# The gateway's external address. Cloud NAT can allocate one itself, but an address it allocates cannot be
# labelled, so one is reserved here (ADR-0035).
resource "google_compute_address" "nat" {
  project      = var.project_id
  name         = "shiptrack-nat"
  region       = var.region
  address_type = "EXTERNAL"
  labels       = var.labels
}

# One gateway with the address above. Logging is limited to errors (cost).
resource "google_compute_router_nat" "this" {
  project                            = var.project_id
  name                               = "shiptrack"
  router                             = google_compute_router.this.name
  region                             = var.region
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = [google_compute_address.nat.self_link]
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Private services access: the range Google carves Cloud SQL's private addresses from, and the
# peering that makes it reachable from the subnet.
resource "google_compute_global_address" "private_services" {
  project       = var.project_id
  name          = "shiptrack-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.private_services_prefix_length
  network       = google_compute_network.this.id
  labels        = var.labels
}

resource "google_service_networking_connection" "private_services" {
  network                 = google_compute_network.this.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]
}
