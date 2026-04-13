variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "region" {
  description = "Short region code (ne, eus)"
  type        = string
  default     = "ne"
}

variable "resource_group_workload" {
  description = "Name of the workload resource group"
  type        = string
  default     = ""
}

variable "log_analytics_workspace" {
  description = "Name of the shared Log Analytics workspace"
  type        = string
  default     = ""
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus2"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "workload" {
  description = "Workload name used in resource naming"
  type        = string
  default     = "ai-agent"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "aks_system_node_vm_size" {
  description = "VM size for AKS system node pool"
  type        = string
  default     = "Standard_D2s_v5"
}

variable "aks_user_node_vm_size" {
  description = "VM size for AKS user node pool"
  type        = string
  default     = "Standard_D4s_v5"
}

variable "aks_user_node_count" {
  description = "Number of nodes in the AKS user node pool"
  type        = number
  default     = 2
}

variable "cosmos_database_name" {
  description = "Cosmos DB database name"
  type        = string
  default     = "conversations"
}

variable "cosmos_container_name" {
  description = "Cosmos DB container name"
  type        = string
  default     = "messages"
}

variable "redis_sku_name" {
  description = "Redis Cache SKU (Basic, Standard, Premium)"
  type        = string
  default     = "Basic"
}

variable "redis_family" {
  description = "Redis Cache family (C for Basic/Standard, P for Premium)"
  type        = string
  default     = "C"
}

variable "redis_capacity" {
  description = "Redis Cache capacity (0-6)"
  type        = number
  default     = 0
}
