variable "name" {
  description = "Container Registry name"
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
  description = "Subnet ID for the private endpoint"
  type        = string
}

variable "acr_dns_zone_id" {
  description = "Private DNS zone ID for ACR (privatelink.azurecr.io)"
  type        = string
}
