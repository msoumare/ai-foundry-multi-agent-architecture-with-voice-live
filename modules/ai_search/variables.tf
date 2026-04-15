variable "name" {
  description = "Azure AI Search service name"
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

variable "sku" {
  description = "Search service SKU (e.g., basic, standard, standard2)"
  type        = string
  default     = "basic"
}

variable "ai_foundry_hub_id" {
  description = "AI Foundry Hub resource ID for private link"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for the private endpoint"
  type        = string
}

variable "search_dns_zone_id" {
  description = "Private DNS zone ID for AI Search (privatelink.search.windows.net)"
  type        = string
}