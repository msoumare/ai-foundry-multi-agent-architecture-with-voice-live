variable "name" {
  description = "Cosmos DB account name"
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

variable "database_name" {
  description = "Database name"
  type        = string
  default     = "conversations"
}

variable "container_name" {
  description = "Container name"
  type        = string
  default     = "messages"
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

variable "cosmosdb_dns_zone_id" {
  description = "Private DNS zone ID for Cosmos DB (privatelink.documents.azure.com)"
  type        = string
}
