variable "project_id" {
  description = "ID of the ShipTrack project. Sensitive so that plan output never prints it."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Region of the subnet, router, and NAT gateway (ADR-0006)."
  type        = string
}

variable "subnet_cidr" {
  description = "Primary range of the subnet: the GKE nodes."
  type        = string
}

variable "pods_cidr" {
  description = "Secondary range for the cluster's pods."
  type        = string
}

variable "services_cidr" {
  description = "Secondary range for the cluster's services."
  type        = string
}

variable "private_services_prefix_length" {
  description = "Prefix length of the range that Google allocates to Cloud SQL (private services access)."
  type        = number
}
