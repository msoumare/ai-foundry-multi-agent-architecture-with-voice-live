variable "name" {
  description = "User Assigned Identity name"
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
  default     = ""
}

variable "acr_id" {
  description = "Container Registry resource ID for AcrPull role"
  type        = string
  default     = ""
}

variable "cosmos_db_account_id" {
  description = "Cosmos DB account resource ID for role assignment"
  type        = string
  default     = ""
}

variable "ai_services_id" {
  description = "AI Services account resource ID for role assignment"
  type        = string
  default     = ""
}

variable "storage_account_id" {
  description = "Storage Account resource ID for role assignment"
  type        = string
  default     = ""
}

variable "ai_search_id" {
  description = "Azure AI Search service resource ID"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
