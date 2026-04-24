variable "ai_services_name" {
  description = "AI Services account name for real-time voice"
  type        = string
}

variable "prevent_ai_services_destroy" {
  description = "Prevent accidental destroy/replace of the real-time AI Services account"
  type        = bool
  default     = true
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
