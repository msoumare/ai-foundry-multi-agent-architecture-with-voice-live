variable "ai_services_name" {
  description = "AI Services account name for Foundry-native Agent Mode voice"
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

variable "user_assigned_identity_id" {
  description = "Resource ID of the user-assigned managed identity to attach"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
