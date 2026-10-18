variable "project_id" {
  description = "ID of the ShipTrack project. Sensitive so that plan output never prints it."
  type        = string
  sensitive   = true
}

variable "alert_email" {
  description = "Address that receives the alerts. Sensitive so that plan output never prints it."
  type        = string
  sensitive   = true
}

variable "labels" {
  description = "Labels for every resource that takes them."
  type        = map(string)
}

variable "namespace" {
  description = "Kubernetes namespace of the workloads (pod restarts and the SLA heartbeat are read from it)."
  type        = string
  default     = "shiptrack"
}

variable "subscriptions" {
  description = "Subscription names by flow (events, notifications), from the pubsub module."
  type        = map(string)
}

variable "dead_letter_subscriptions" {
  description = "Names of the subscriptions that hold dead letters, by flow, from the pubsub module."
  type        = map(string)
}

variable "availability_target" {
  description = "Availability objective of the API (modern design 11.1). The burn-rate alerts divide its error budget."
  type        = number
  default     = 0.995
}
