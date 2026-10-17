variable "project_id" {
  description = "ID of the ShipTrack project. Sensitive so that plan output never prints it."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Location of the cluster (ADR-0006)."
  type        = string
  default     = "us-central1"
}

variable "namespace" {
  description = "Kubernetes namespace of the workloads. The cluster root's workload bindings name the same one."
  type        = string
  default     = "shiptrack"
}
