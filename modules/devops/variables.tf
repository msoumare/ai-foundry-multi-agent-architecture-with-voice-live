variable "name" {
  description = "Name of the VMSS"
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

variable "subnet_id" {
  description = "Subnet ID for the VMSS"
  type        = string
}

variable "admin_username" {
  description = "Admin username for VMs"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "SSH public key for VMs"
  type        = string
  sensitive   = true
}

variable "vm_size" {
  description = "VM size for the scale set"
  type        = string
  default     = "Standard_D4s_v5"
}

variable "instance_count" {
  description = "Number of instances"
  type        = number
  default     = 1
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB"
  type        = number
  default     = 128
}

variable "source_image_reference" {
  description = "Source image reference"
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

variable "identity_ids" {
  description = "List of user-assigned identity IDs"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}