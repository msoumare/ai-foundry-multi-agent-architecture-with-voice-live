resource "azurerm_orchestrated_virtual_machine_scale_set" "devops" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  platform_fault_domain_count = 1
  priority = "Regular"
  tags     = var.tags

  os_profile {
    linux_configuration {
      computer_name_prefix           = "devops"
      admin_username                 = var.admin_username
      disable_password_authentication = true

      admin_ssh_key {
        public_key = var.ssh_public_key
        username   = var.admin_username
      }
    }
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

      dynamic "public_ip_address" {
        for_each = var.enable_public_ip ? [1] : []
        content {
          name                    = "pip-devops"
          idle_timeout_in_minutes = 10
          version                 = "IPv4"
          sku_name                = "Standard_Regional"
        }
      }
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = var.identity_ids
  }

  sku_name  = var.vm_size
  instances = var.instance_count

  extension {
    name                       = "install-devops-agent"
    publisher                  = "Microsoft.Azure.Extensions"
    type                       = "CustomScript"
    type_handler_version       = "2.1"

    protected_settings = jsonencode({
      "script" = base64encode(join("\n", [
        "#!/bin/bash",
        "export AZDO_URL='${var.azdo_url}'",
        "export AZDO_POOL='${var.azdo_pool}'",
        "export AZDO_AGENT_NAME='${var.azdo_agent_name}'",
        "export AZDO_PAT='${var.azdo_pat_token}'",
        "export VMSS_ADMIN_USERNAME='${var.admin_username}'",
        file("${path.module}/install-agent.sh")
      ]))
    })
  }
}