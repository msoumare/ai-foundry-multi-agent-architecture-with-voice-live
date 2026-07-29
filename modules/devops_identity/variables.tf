variable "name" {
  description = "DevOps User Assigned Identity name"
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

variable "key_vault_id" {
  description = "Key Vault resource ID for role assignment"
  type        = string
}

variable "acr_id" {
  description = "Container Registry resource ID for AcrPush role"
  type        = string
}

variable "ai_services_id" {
  description = "Optional AI Services (Foundry account) resource ID for Foundry RBAC assignment"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
