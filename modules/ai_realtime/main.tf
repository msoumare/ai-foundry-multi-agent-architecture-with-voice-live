terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

# AI Services account in Sweden Central for the Voice Live API (gpt-4o-realtime-preview).
# Public network access is enabled because real-time audio (WebRTC) connections originate
# from end-user clients and cannot be routed over the private VNet.
resource "azurerm_cognitive_account" "ai_realtime" {
  name                          = var.ai_services_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  kind                          = "AIServices"
  sku_name                      = "S0"
  custom_subdomain_name         = var.ai_services_name
  local_auth_enabled            = false
  public_network_access_enabled = true
  tags                          = var.tags
}

resource "azurerm_cognitive_deployment" "gpt4o_realtime" {
  name                 = "gpt-4o-realtime"
  cognitive_account_id = azurerm_cognitive_account.ai_realtime.id

  model {
    format  = "OpenAI"
    name    = "gpt-4o-realtime"
    version = "2025-08-28"
  }

  sku {
    name     = "GlobalStandard"
    capacity = 1
  }
}


