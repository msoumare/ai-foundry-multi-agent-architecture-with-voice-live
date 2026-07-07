variable "name" {
  description = "Name of the Application Gateway for Containers traffic controller."
  type        = string
}

variable "frontend_name" {
  description = "Name of the Application Gateway for Containers frontend resource."
  type        = string
}

variable "association_name" {
  description = "Name of the Application Gateway for Containers association resource."
  type        = string
}

variable "location" {
  description = "Azure region for the Application Gateway for Containers resources."
  type        = string
}

variable "resource_group_id" {
  description = "Resource ID of the resource group that owns the Application Gateway for Containers resources."
  type        = string
}

variable "association_subnet_id" {
  description = "Delegated subnet resource ID used for the Application Gateway for Containers association."
  type        = string
}

variable "tags" {
  description = "Tags applied to the Application Gateway for Containers resources."
  type        = map(string)
  default     = {}
}
