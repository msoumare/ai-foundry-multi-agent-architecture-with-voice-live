variable "ai_services_name" {
  description = "AI Services account name"
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
  description = "User Assigned Identity resource ID for Foundry agents"
  type        = string
}


