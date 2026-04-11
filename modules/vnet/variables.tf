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

variable "address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "aks_subnet_prefixes" {
  description = "Address prefixes for the AKS subnet"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "private_endpoints_subnet_prefixes" {
  description = "Address prefixes for the private endpoints subnet"
  type        = list(string)
  default     = ["10.0.2.0/24"]
}

variable "devops_subnet_prefixes" {
  description = "Address prefixes for the devops subnet"
  type        = list(string)
  default     = ["10.0.3.0/24"]
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}