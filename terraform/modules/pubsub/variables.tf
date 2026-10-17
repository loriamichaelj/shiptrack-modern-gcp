variable "project_id" {
  description = "ID of the ShipTrack project. Sensitive so that plan output never prints it."
  type        = string
  sensitive   = true
}

variable "project_number" {
  description = "Number of the project. Names Pub/Sub's service agent, which dead-lettering needs."
  type        = string
  sensitive   = true
}

variable "labels" {
  description = "Labels for the topics and subscriptions."
  type        = map(string)
}
