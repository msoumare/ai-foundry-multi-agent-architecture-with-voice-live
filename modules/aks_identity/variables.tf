variable "name" {
  description = "AKS compute User Assigned Identity name"
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
  description = "Container Registry resource ID for AcrPull role"
  type        = string
}

variable "cosmos_db_account_id" {
  description = "Cosmos DB account resource ID for role assignment"
  type        = string
}

variable "redis_id" {
  description = "Redis Cache resource ID for Entra access policy assignment"
  type        = string
}

variable "ai_search_id" {
  description = "Azure AI Search service resource ID"
  type        = string
}

variable "foundry_ai_services_id" {
  description = "Foundry-linked Azure AI Services resource ID for OpenAI role assignment"
  type        = string
}

variable "realtime_ai_services_id" {
  description = "Azure AI Realtime Services resource ID for OpenAI role assignment"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
