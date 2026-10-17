variable "project_id" {
  description = "ID of the ShipTrack project. Sensitive so that plan output never prints it."
  type        = string
  sensitive   = true
}

variable "project_number" {
  description = "Number of the ShipTrack project. Used in the state bucket name and in Workload Identity principals."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9]+$", var.project_number))
    error_message = "project_number must be a number."
  }
}

variable "region" {
  description = "Region of the state bucket."
  type        = string
  default     = "us-central1"
}

variable "workload_identity_pool_id" {
  description = "ID of the Workload Identity pool that trusts GitHub. Created by hand (README)."
  type        = string
  default     = "github"
}

variable "github_org" {
  description = "GitHub user or organization that owns the repository."
  type        = string
}

variable "github_owner_id" {
  description = "Numeric ID of the GitHub owner. The OIDC sub claim carries the owner and repository IDs."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must be a number."
  }
}

variable "github_repo" {
  description = "Name of this repository."
  type        = string
  default     = "shiptrack-modern-gcp"
}

variable "github_repository_id" {
  description = "Numeric ID of this repository."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must be a number."
  }
}
