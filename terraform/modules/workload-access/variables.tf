variable "project_id" {
  description = "ID of the ShipTrack project. Sensitive so that plan output never prints it."
  type        = string
  sensitive   = true
}

variable "project_number" {
  description = "Number of the project. Part of the workload's IAM principal."
  type        = string
  sensitive   = true
}

variable "namespace" {
  description = "Kubernetes namespace of the workload."
  type        = string
}

variable "kubernetes_service_account" {
  description = "Name of the Kubernetes service account the workload runs as."
  type        = string
}

variable "topics_publisher" {
  description = "Names of the topics the workload may publish to."
  type        = set(string)
  default     = []
}

variable "subscriptions_subscriber" {
  description = "Names of the subscriptions the workload may pull from and acknowledge on."
  type        = set(string)
  default     = []
}

variable "secrets_accessor" {
  description = "IDs of the secrets the workload may read."
  type        = set(string)
  default     = []
}

# The bucket name is known only after the bucket exists, so it is a value and a flag, not a set.
variable "bucket_object_user" {
  description = "Whether the workload may read and write objects in the bucket."
  type        = bool
  default     = false
}

variable "bucket_name" {
  description = "Name of the bucket. Used only when bucket_object_user is true."
  type        = string
  default     = null
  sensitive   = true
}

variable "may_sign_as" {
  description = "Email of the service account the workload may create tokens for, to sign URLs. Null for none."
  type        = string
  default     = null
  sensitive   = true
}
