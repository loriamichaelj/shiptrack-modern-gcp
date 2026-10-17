variable "project_id" {
  description = "ID of the ShipTrack project. Sensitive so that plan output never prints it."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Location of the bucket (ADR-0006)."
  type        = string
}

variable "labels" {
  description = "Labels for the bucket."
  type        = map(string)
}

variable "protection" {
  description = "Keeps the bucket from being destroyed while it holds objects. destroy-proof-of-delivery-storage turns it off inside its approved run (ADR-0027)."
  type        = bool
  default     = true
}
