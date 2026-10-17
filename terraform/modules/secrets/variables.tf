variable "project_id" {
  description = "ID of the ShipTrack project. Sensitive so that plan output never prints it."
  type        = string
  sensitive   = true
}

variable "labels" {
  description = "Labels for the secrets."
  type        = map(string)
}

variable "host" {
  description = "Private address of the database."
  type        = string
}

variable "dbname" {
  description = "Name of the application database."
  type        = string
}

variable "admin_user" {
  description = "Name of the database administrator."
  type        = string
}

variable "passwords" {
  description = "Password for each of app, migrator, and admin. Written with a write-only argument, so none enters state."
  type        = map(string)
  ephemeral   = true
}

variable "credentials_version" {
  description = "Raise to write the credentials again. The write-only argument is sent only when this changes."
  type        = number
}
