variable "project_id" {
  description = "ID of the ShipTrack project. Sensitive so that plan output never prints it."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Location of the cluster (ADR-0006)."
  type        = string
}

variable "network" {
  description = "Self link of the VPC."
  type        = string
}

variable "subnetwork" {
  description = "Self link of the subnet the nodes use."
  type        = string
}

variable "pods_range_name" {
  description = "Name of the subnet's secondary range for pods."
  type        = string
}

variable "services_range_name" {
  description = "Name of the subnet's secondary range for services."
  type        = string
}

variable "node_service_account" {
  description = "Email of the service account the nodes run as."
  type        = string
}

variable "labels" {
  description = "Labels for the cluster."
  type        = map(string)
}

variable "deletion_protection" {
  description = "Protects the cluster from deletion. destroy-cluster turns it off inside its approved run (ADR-0027)."
  type        = bool
  default     = true
}
