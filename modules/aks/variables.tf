variable "name" {
  description = "AKS cluster name"
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

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for Container Insights"
  type        = string
}

variable "user_assigned_identity_id" {
  description = "User Assigned Identity resource ID"
  type        = string
}

variable "system_node_vm_size" {
  description = "VM size for system node pool"
  type        = string
  default     = "Standard_D2s_v5"
}

variable "user_node_vm_size" {
  description = "VM size for user node pool"
  type        = string
  default     = "Standard_D4s_v5"
}

variable "user_node_count" {
  description = "Number of nodes in user node pool"
  type        = number
  default     = 2
}

variable "vnet_subnet_id" {
  description = "Subnet ID for AKS cluster"
  type        = string
}

variable "private_cluster_enabled" {
  description = "Enable private cluster for AKS"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}