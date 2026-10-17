variable "project_id" {
  description = "ID of the ShipTrack project. Sensitive so that plan output never prints it."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Region of the load balancer, its address, and its policy (ADR-0006)."
  type        = string
}

variable "network_id" {
  description = "ID of the VPC that holds the proxy-only subnet."
  type        = string
}

variable "name" {
  description = "Name of the address and the security policy. The Gateway manifests in deploy/gateway name the same two."
  type        = string
  default     = "shiptrack-ui"
}

variable "proxy_only_cidr" {
  description = "Range of the subnet the regional load balancer's proxies use. It must not overlap the other ranges of the VPC."
  type        = string
  default     = "10.23.0.0/24"
}

variable "closed_range" {
  description = "The range the allow rule holds while the port is closed: a documentation address that no client has (RFC 5737). ops-ui-port sets the real range from a secret and puts this back to close."
  type        = string
  default     = "192.0.2.1/32"
}
