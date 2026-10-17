# What a global external Application Load Balancer needs before the Gateway in deploy/gateway can create it
# (ADR-0031): a reserved address, a Google-managed certificate for the hostname that address gives, and a
# Cloud Armor policy that admits one address and nothing else. The Gateway, the route, and the policies that
# bind these are Kubernetes objects applied by deploy-app, so Terraform makes no load balancer itself.
#
# The API has no login, so the load balancer must not be open. The policy denies everyone, and one allow rule
# admits the range in a masked secret. The rule's range is changed by the ops-ui-port workflow (open, close),
# not by Terraform, which is why the rule ignores changes to its match.

resource "google_compute_global_address" "ui" {
  project      = var.project_id
  name         = var.name
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

# The hostname is the address with dashes, under sslip.io, a public name that resolves to the address in it.
# Google validates the certificate by the load balancer that serves the name, so no DNS record is needed
# (ADR-0031). It can take up to an hour to become active after the Gateway exists.
resource "google_compute_managed_ssl_certificate" "ui" {
  project = var.project_id
  name    = var.name

  managed {
    domains = ["${replace(google_compute_global_address.ui.address, ".", "-")}.sslip.io"]
  }
}

resource "google_compute_security_policy" "ui" {
  #checkov:skip=CKV_GCP_73: Cloud Armor's managed rule sets and adaptive protection cost per request or per month; the policy admits one address, which is the control.
  project     = var.project_id
  name        = var.name
  description = "Admits one address to the ShipTrack UI and denies everyone else"
  type        = "CLOUD_ARMOR"

  rule {
    action      = "deny(403)"
    priority    = 2147483647
    description = "Default: deny"

    match {
      versioned_expr = "SRC_IPS_V1"

      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}

resource "google_compute_security_policy_rule" "allow_owner" {
  project         = var.project_id
  security_policy = google_compute_security_policy.ui.name
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
