terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    azapi = {
      source = "azure/azapi"
    }
  }
}

resource "azurerm_cognitive_account" "ai_services" {
  name                  = var.ai_services_name
  location              = var.location
  resource_group_name   = var.resource_group_name
  kind                  = "AIServices"
  sku_name              = "S0"
  custom_subdomain_name = var.ai_services_name
  local_auth_enabled    = false
  public_network_access_enabled = false
  tags                  = var.tags
}

resource "azapi_update_resource" "ai_services_project_management" {
  type        = "Microsoft.CognitiveServices/accounts@2024-10-01"
  resource_id = azurerm_cognitive_account.ai_services.id

  body = {
    properties = {
      allowProjectManagement = true
    }
  }

  depends_on = [azurerm_cognitive_account.ai_services]
}

resource "azurerm_cognitive_deployment" "gpt4o" {
  name                 = "gpt-4o"
  cognitive_account_id = azurerm_cognitive_account.ai_services.id

  model {
    format  = "OpenAI"
    name    = "gpt-4o"
    version = "2024-11-20"
  }

  sku {
    name     = "GlobalStandard"
    capacity = 1
  }
}

resource "azurerm_cognitive_deployment" "gpt41mini" {
  name                 = "gpt-4.1-mini"
  cognitive_account_id = azurerm_cognitive_account.ai_services.id

  model {
    format  = "OpenAI"
    name    = "gpt-4.1-mini"
    version = "2025-04-14"
  }

  sku {
    name     = "GlobalStandard"
    capacity = 1
  }
}

resource "azurerm_private_endpoint" "ai_services" {
  name                = "pe-ai-${var.ai_services_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "ai-services-connection"
    private_connection_resource_id = azurerm_cognitive_account.ai_services.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-ai-${var.ai_services_name}"
    private_dns_zone_ids = [
      var.ai_services_dns_zone_id,
      var.ai_openai_dns_zone_id,
      var.ai_services_ai_dns_zone_id,
    ]
  }

  tags = var.tags

  depends_on = [
    azurerm_cognitive_account.ai_services,
    azurerm_cognitive_deployment.gpt4o,
    azurerm_cognitive_deployment.gpt41mini,
  ]
}
