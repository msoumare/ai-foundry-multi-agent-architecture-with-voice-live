# Uniform VMSS - agent lifecycle is managed by Azure DevOps native VMSS pool integration.
# Link this VMSS to an agent pool via: Azure DevOps → Project Settings → Agent pools → New pool → Azure Virtual Machine Scale Set.
# Azure DevOps will automatically install, register, and deregister the agent on each instance.
resource "azurerm_linux_virtual_machine_scale_set" "devops" {
  name                   = var.name
  location               = var.location
  resource_group_name    = var.resource_group_name
  sku                    = var.vm_size
  instances              = var.instance_count
  single_placement_group = false
  admin_username         = var.admin_username
  # Manual upgrade mode is required for Azure DevOps VMSS pool integration.
  upgrade_mode = "Manual"
  tags         = var.tags

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = var.source_image_reference.publisher
    offer     = var.source_image_reference.offer
    sku       = var.source_image_reference.sku
    version   = var.source_image_reference.version
  }

  network_interface {
    name    = "nic-devops"
    primary = true

    ip_configuration {
      name      = "ipconfig"
      primary   = true
      subnet_id = var.subnet_id
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = var.identity_ids
  }

  # Bootstrap build tools at first boot without using a VM extension,
  # so Azure DevOps can manage its own VMSS agent extension lifecycle.
  custom_data = base64encode(file("${path.module}/install-agent.sh"))
}