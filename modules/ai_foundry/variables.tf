variable "hub_name" {
  description = "AI Foundry Hub name"
  type        = string
}

variable "project_name" {
  description = "AI Foundry Project name"
  type        = string
}

variable "ai_services_name" {
  description = "AI Services account name"
  type        = string
}

variable "storage_account_name" {
  description = "Storage account name for AI Foundry"
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
  description = "Key Vault resource ID"
  type        = string
}

variable "app_insights_id" {
  description = "Application Insights resource ID"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
