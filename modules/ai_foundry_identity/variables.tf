variable "name" {
  description = "Foundry User Assigned Identity name"
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

variable "storage_account_id" {
  description = "Storage Account resource ID for artifacts and datasets"
  type        = string
}

variable "acr_id" {
  description = "Container Registry resource ID for hosted agent image pulls"
  type        = string
}

variable "ai_search_id" {
  description = "Azure AI Search service resource ID"
  type        = string
}

variable "cosmos_db_account_id" {
  description = "Cosmos DB account resource ID"
  type        = string
}

variable "ai_services_id" {
  description = "AI Services (Foundry) resource ID"
  type        = string
}

variable "ai_services_principal_id" {
  description = "Principal ID of AI Services managed identity for ACR pull role assignment"
  type        = string
}

variable "foundry_project_id" {
  description = "Optional Foundry project/workspace scope resource ID for Foundry User role assignment"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
