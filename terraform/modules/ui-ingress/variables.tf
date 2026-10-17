variable "project_id" {
  description = "ID of the ShipTrack project. Sensitive so that plan output never prints it."
  type        = string
  sensitive   = true
}

variable "name" {
  description = "Name of the address, the certificate, and the security policy. The Gateway manifests in deploy/gateway name the same three."
  type        = string
  default     = "shiptrack-ui"
}

variable "closed_range" {
  description = "The range the allow rule holds while the port is closed: a documentation address that no client has (RFC 5737). ops-ui-port sets the real range from a secret and puts this back to close."
  type        = string
  default     = "192.0.2.1/32"
}
