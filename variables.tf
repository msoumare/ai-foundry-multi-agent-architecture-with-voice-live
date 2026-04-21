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

variable "azdo_url" {
  description = "Azure DevOps organization URL"
  type        = string
  default     = ""
}

variable "azdo_pool" {
  description = "Azure DevOps agent pool name"
  type        = string
  default     = "default"
}

variable "azdo_agent_name" {
  description = "Azure DevOps agent name override"
  type        = string
  default     = ""
}

variable "azdo_pat_token" {
  description = "Azure DevOps PAT token for self-hosted agent registration"
  type        = string
  default     = ""
  sensitive   = true
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

variable "address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
}

variable "aks_subnet_prefixes" {
  description = "Address prefixes for the AKS subnet"
  type        = list(string)
}

variable "private_endpoints_subnet_prefixes" {
  description = "Address prefixes for the private endpoints subnet"
  type        = list(string)
}

variable "devops_subnet_prefixes" {
  description = "Address prefixes for the devops subnet"
  type        = list(string)
}

variable "bastion_subnet_prefixes" {
  description = "Address prefixes for the Azure Bastion subnet; Azure requires the subnet to be named AzureBastionSubnet and be at least /26"
  type        = list(string)
}

variable "enable_p2s_vpn" {
  description = "Enable Point-to-Site VPN gateway for local development access"
  type        = bool
  default     = false
}

variable "gateway_subnet_prefixes" {
  description = "Address prefixes for the GatewaySubnet used by the VPN gateway"
  type        = list(string)
  default     = []
}

variable "enable_private_dns_resolver" {
  description = "Enable Azure Private DNS Resolver with an inbound endpoint"
  type        = bool
  default     = true
}

variable "dns_resolver_subnet_prefixes" {
  description = "Address prefixes for the Private DNS Resolver inbound endpoint subnet (minimum /28)"
  type        = list(string)
  default     = []
}

variable "p2s_vpn_client_address_space" {
  description = "Client address pool for Point-to-Site VPN clients"
  type        = list(string)
  default     = ["172.16.201.0/24"]
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
