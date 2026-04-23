variable "name" {
  description = "Foundry project resource name"
  type        = string
}

variable "display_name" {
  description = "Foundry project display name"
  type        = string
}

variable "description" {
  description = "Foundry project description"
  type        = string
  default     = "Managed by Terraform"
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "ai_services_account_id" {
  description = "Parent AI Services account resource ID"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
