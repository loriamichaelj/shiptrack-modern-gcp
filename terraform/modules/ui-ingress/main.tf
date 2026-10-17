# What a regional external Application Load Balancer needs before the Gateway in deploy/gateway can create it
# (ADR-0031): a subnet for its proxies, a reserved regional address, and a Cloud Armor policy that admits one
# address and nothing else. The Gateway, the route, and the policies that bind these are Kubernetes objects
# applied by deploy-app, so Terraform makes no load balancer itself.
#
# The API has no login, so the load balancer must not be open. The policy denies everyone, and one allow rule
# admits the range in a masked secret. The rule's range is changed by the ops-ui-port workflow (open, close),
# not by Terraform, which is why the rule ignores changes to its match.

# The load balancer's proxies take their addresses from this subnet, and Cloud Armor and the health checks see
# them there.
resource "google_compute_subnetwork" "proxy_only" {
  project       = var.project_id
  name          = "${var.name}-proxy-only"
  region        = var.region
  network       = var.network_id
  ip_cidr_range = var.proxy_only_cidr
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

resource "google_compute_address" "ui" {
  project      = var.project_id
  name         = var.name
  region       = var.region
  address_type = "EXTERNAL"
}

resource "google_compute_region_security_policy" "ui" {
  project     = var.project_id
  name        = var.name
  region      = var.region
  description = "Admits one address to the ShipTrack UI and denies everyone else"
  type        = "CLOUD_ARMOR"
}

# A regional policy starts with a default rule that allows everything. This takes its place and denies.
resource "google_compute_region_security_policy_rule" "default_deny" {
  project         = var.project_id
  region          = var.region
  security_policy = google_compute_region_security_policy.ui.name
  priority        = 2147483647
  action          = "deny(403)"
  description     = "Default: deny"

  match {
    versioned_expr = "SRC_IPS_V1"

    config {
      src_ip_ranges = ["*"]
    }
  }
}

resource "google_compute_region_security_policy_rule" "allow_owner" {
  project         = var.project_id
  region          = var.region
  security_policy = google_compute_region_security_policy.ui.name
  priority        = 1000
  action          = "allow"
  description     = "The owner's address, set by ops-ui-port; closed when it holds the unroutable range"

  match {
    versioned_expr = "SRC_IPS_V1"

    config {
      src_ip_ranges = [var.closed_range]
    }
  }

  lifecycle {
    ignore_changes = [match]
  }
}
