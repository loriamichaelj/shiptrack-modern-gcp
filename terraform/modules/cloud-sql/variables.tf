variable "project_id" {
  description = "ID of the ShipTrack project. Sensitive so that plan output never prints it."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Region of the instance (ADR-0006)."
  type        = string
}

variable "network_id" {
  description = "ID of the VPC the instance gets its private address in."
  type        = string
}

variable "private_services_connection" {
  description = "ID of the private services access peering. The instance cannot be created before it exists."
  type        = string
}

variable "labels" {
  description = "Labels for the instance."
  type        = map(string)
}

variable "tier" {
  description = "Machine tier (ADR-0008): a shared core."
  type        = string
  default     = "db-f1-micro"
}

variable "disk_size_gb" {
  description = "Size of the data disk in GiB."
  type        = number
  default     = 10
}

variable "deletion_protection" {
  description = "Protects the instance from deletion, in Terraform and in Google Cloud. destroy-cloud-sql turns it off inside its approved run (ADR-0027)."
  type        = bool
  default     = true
}

variable "admin_user" {
  description = "Name of the administrator that deploy-app's db-init Job connects as."
  type        = string
  default     = "shiptrack_admin"
}

variable "admin_password" {
  description = "Password of the administrator. Written with a write-only argument, so it never enters state."
  type        = string
  ephemeral   = true
}

variable "admin_password_version" {
  description = "Raise to write admin_password again. The write-only argument is sent only when this changes."
  type        = number
}
