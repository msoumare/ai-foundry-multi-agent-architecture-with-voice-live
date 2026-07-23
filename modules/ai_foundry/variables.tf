variable "ai_services_name" {
  description = "AI Services account name"
  type        = string
}

variable "storage_account_id" {
  description = "Storage account resource ID for Foundry artifacts and datasets"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID used for AI Services diagnostics"
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

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for private endpoints"
  type        = string
}

variable "ai_services_dns_zone_id" {
  description = "Private DNS zone ID for AI Services (privatelink.cognitiveservices.azure.com)"
  type        = string
}

variable "ai_openai_dns_zone_id" {
  description = "Private DNS zone ID for OpenAI (privatelink.openai.azure.com)"
  type        = string
}

variable "ai_services_ai_dns_zone_id" {
  description = "Private DNS zone ID for Services AI (privatelink.services.ai.azure.com)"
  type        = string
}

variable "user_assigned_identity_id" {
  description = "User assigned identity ID for AI Foundry"
  type        = string
}

variable "cognitive_account_project_name" {
  description = "Cognitive account project name"
  type        = string
}

variable "project_description" {
  description = "Project description"
  type        = string
}

variable "project_display_name" {
  description = "Project display name"
  type        = string
}