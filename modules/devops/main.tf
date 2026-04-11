resource "azurerm_virtual_machine_scale_set" "devops" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = var.vm_size
  instances           = var.instance_count
  upgrade_mode        = "Manual"
  overprovision       = false
  tags                = var.tags


  network_interface {
    name    = "nic-devops"
    primary = true

    ip_configuration {
      name      = "ipconfig"
      primary   = true
      subnet_id = var.subnet_id
    }
  }

  storage_profile_os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = var.source_image_reference.publisher
    offer     = var.source_image_reference.offer
    sku       = var.source_image_reference.sku
    version   = var.source_image_reference.version
  }

  os_profile {
    computer_name_prefix = "devops"
    admin_username       = var.admin_username
    admin_password       = var.admin_password
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  identity {
    type         = "UserAssigned"
    identity_ids = var.identity_ids
  }

  extension_profile {
    # VM Extension for Azure DevOps Agent Installation
    extension {
      name                       = "install-devops-agent"
      publisher                  = "Microsoft.Azure.Extensions"
      type                       = "CustomScript"
      type_handler_version       = "2.1"
      auto_upgrade_minor_version = true

      settings = jsonencode({
        "fileUris"         = []
        "commandToExecute" = "bash /opt/azure-devops-agent/install-agent.sh"
      })

      protected_settings = jsonencode({
        "script" = base64encode(file("${path.module}/install-agent.sh"))
      })
    }
  }
}