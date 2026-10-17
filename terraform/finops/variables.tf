variable "project_id" {
  description = "ID of the ShipTrack project. Sensitive so that plan output never prints it."
  type        = string
  sensitive   = true
}

variable "project_number" {
  description = "Number of the ShipTrack project. The budget is filtered to this project."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9]+$", var.project_number))
    error_message = "project_number must be a number."
  }
}

variable "region" {
  description = "Location of the billing export dataset (ADR-0006)."
  type        = string
  default     = "us-central1"
}

variable "billing_account_id" {
  description = "ID of the billing account the project is linked to. Sensitive so that plan output never prints it."
  type        = string
  sensitive   = true
}

variable "alert_email" {
  description = "Address that receives budget alerts. Sensitive so that plan output never prints it."
  type        = string
  sensitive   = true
}

variable "monthly_budget_usd" {
  description = "Monthly budget in US dollars (ADR-0028): about 1.5 times the baseline in design section 13."
  type        = number
  default     = 50
}
