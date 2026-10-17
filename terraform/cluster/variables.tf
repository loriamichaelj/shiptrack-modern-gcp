variable "project_id" {
  description = "ID of the ShipTrack project. Sensitive so that plan output never prints it."
  type        = string
  sensitive   = true
}

variable "project_number" {
  description = "Number of the ShipTrack project. Names the state bucket and the workloads' IAM principals."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9]+$", var.project_number))
    error_message = "project_number must be a number."
  }
}

variable "region" {
  description = "Location of the cluster (ADR-0006)."
  type        = string
  default     = "us-central1"
}

variable "namespace" {
  description = "Kubernetes namespace of the workloads. The addons root creates it."
  type        = string
  default     = "shiptrack"
}

variable "deletion_protection" {
  description = "Protects the cluster from deletion. destroy-cluster sets it to false inside its approved run (ADR-0027); every normal apply leaves it true."
  type        = bool
  default     = true
}
