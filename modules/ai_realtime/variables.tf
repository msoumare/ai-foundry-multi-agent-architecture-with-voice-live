variable "ai_services_name" {
  description = "AI Services account name for real-time voice"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

variable "user_assigned_identity_id" {
  description = "User Assigned Identity resource ID for Foundry agents"
  type        = string
}
