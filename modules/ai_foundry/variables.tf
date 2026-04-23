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

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for private endpoints"
  type        = string
}

variable "ai_services_dns_zone_id" {
  description = "Private DNS zone ID for AI Services (privatelink.cognitiveservices.azure.com)"
  type        = string
}

variable "storage_dns_zone_id" {
  description = "Private DNS zone ID for Storage Blob (privatelink.blob.core.windows.net)"
  type        = string
}

variable "hub_dns_zone_id" {
  description = "Private DNS zone ID for ML workspaces (privatelink.api.azureml.ms)"
  type        = string
}

variable "hub_notebooks_dns_zone_id" {
  description = "Private DNS zone ID for ML notebooks (privatelink.notebooks.azure.net)"
  type        = string
}

variable "user_assigned_identity_id" {
  description = "Resource ID of the platform user-assigned managed identity (AI Foundry hub/project)"
  type        = string
}

variable "user_assigned_identity_principal_id" {
  description = "Principal ID of the platform user-assigned managed identity (for role assignments)"
  type        = string
}
