variable "project_id" {
  description = "ID of the ShipTrack project. Sensitive so that plan output never prints it."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Region of every resource (ADR-0006)."
  type        = string
  default     = "us-central1"
}

# Private ranges. They hold no identifier, so they have defaults. The subnet's nodes, the cluster's
# pods and services, and Cloud SQL's private range must not overlap each other.
variable "subnet_cidr" {
  description = "Primary range of the subnet: the GKE nodes."
  type        = string
  default     = "10.20.0.0/24"
}

variable "pods_cidr" {
  description = "Secondary range for the cluster's pods."
  type        = string
  default     = "10.21.0.0/22"
}

variable "services_cidr" {
  description = "Secondary range for the cluster's services."
  type        = string
  default     = "10.22.0.0/24"
}

variable "private_services_prefix_length" {
  description = "Prefix length of the range that Google allocates to Cloud SQL (private services access)."
  type        = number
  default     = 24
}

variable "deletion_protection" {
  description = "Protects Cloud SQL from deletion. destroy-cloud-sql sets it to false inside its approved run (ADR-0027); every normal apply leaves it true."
  type        = bool
  default     = true
}

variable "db_credentials_version" {
  description = "Raise to generate and write new database passwords. They are write-only, so Terraform sends them only when this changes."
  type        = number
  default     = 1
}

variable "project_number" {
  description = "Number of the ShipTrack project. Names Pub/Sub's service agent. Sensitive so that plan output never prints it."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9]+$", var.project_number))
    error_message = "project_number must be a number."
  }
}

variable "proof_of_delivery_protection" {
  description = "Keeps the proof-of-delivery bucket from being destroyed while it holds objects. destroy-proof-of-delivery-storage sets it to false inside its approved run (ADR-0027); every normal apply leaves it true."
  type        = bool
  default     = true
}
