terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

# Foundry-native Agent Mode account for Voice Live.
# This account is dedicated to agent-mode integration (no explicit gpt-realtime model deployment).
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

  identity {
    type         = "UserAssigned"
    identity_ids = [var.user_assigned_identity_id]
  }

  lifecycle {
    # Temporary guard: keep the existing account in place while projects under the account
    # are not managed by Terraform.
    ignore_changes = all
  }
}
