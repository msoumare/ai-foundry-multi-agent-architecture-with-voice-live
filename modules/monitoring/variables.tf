variable "name" {
  description = "Log Analytics workspace name"
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

variable "app_insights_name" {
  description = "Application Insights name"
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

variable "log_analytics_dns_zone_id" {
  description = "Private DNS zone ID for Log Analytics (privatelink.oms.opinsights.azure.com)"
  type        = string
}
