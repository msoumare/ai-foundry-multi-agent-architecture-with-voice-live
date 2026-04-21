variable "workload" {
  description = "Workload name"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "region" {
  description = "Short region code"
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

variable "virtual_network_name" {
  description = "Name of the target virtual network"
  type        = string
}

variable "gateway_subnet_prefixes" {
  description = "Address prefixes for the GatewaySubnet used by the VPN gateway"
  type        = list(string)
}

variable "p2s_vpn_client_address_space" {
  description = "Client address pool for Point-to-Site VPN clients"
  type        = list(string)
}

variable "p2s_dns_servers" {
  description = "Optional DNS servers to push to P2S VPN clients"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
