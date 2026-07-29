variable "name" {
  description = "Key Vault name"
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

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for the private endpoint"
  type        = string
}

variable "keyvault_dns_zone_id" {
  description = "Private DNS zone ID for Key Vault (privatelink.vaultcore.azure.net)"
  type        = string
}

variable "devops_ssh_private_key_secret_name" {
  description = "Name of the secret that stores the DevOps VMSS private key"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
