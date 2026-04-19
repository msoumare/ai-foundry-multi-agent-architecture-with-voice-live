variable "workload" {
  description = "Workload name"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "region" {
  description = "Azure region"
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

variable "name" {
  description = "Virtual network name"
  type        = string
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

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}