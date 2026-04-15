variable "name" {
  description = "Redis Cache name"
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

variable "sku_name" {
  description = "Redis SKU (Basic, Standard, Premium)"
  type        = string
  default     = "Basic"
}

variable "family" {
  description = "Redis family (C for Basic/Standard, P for Premium)"
  type        = string
  default     = "C"
}

variable "capacity" {
  description = "Redis capacity (0-6)"
  type        = number
  default     = 0
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

variable "redis_dns_zone_id" {
  description = "Private DNS zone ID for Redis (privatelink.redis.cache.windows.net)"
  type        = string
}
