terraform {
  required_providers {
    azapi = {
      source = "azure/azapi"
    }
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

resource "azurerm_storage_account" "ai" {
  name                      = var.storage_account_name
  location                  = var.location
  resource_group_name       = var.resource_group_name
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  account_kind              = "StorageV2"
  min_tls_version           = "TLS1_2"
  shared_access_key_enabled = false
  public_network_access_enabled = false
  tags                      = var.tags
}

# Grant the user-assigned identity access to AI Foundry storage
resource "azurerm_role_assignment" "uai_storage_access" {
  scope                = azurerm_storage_account.ai.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.user_assigned_identity_principal_id
  principal_type       = "ServicePrincipal"
}

# Grant the user-assigned identity access to AI Services
resource "azurerm_role_assignment" "uai_cognitive_services_user" {
  scope                = azurerm_cognitive_account.ai_services.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = var.user_assigned_identity_principal_id
  principal_type       = "ServicePrincipal"
}

# Keep the generic Cognitive Services role for Foundry platform compatibility
# on hub/project connection and service metadata operations.
resource "azurerm_role_assignment" "uai_cognitive_services_user_general" {
  scope                = azurerm_cognitive_account.ai_services.id
  role_definition_name = "Cognitive Services User"
  principal_id         = var.user_assigned_identity_principal_id
  principal_type       = "ServicePrincipal"
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

resource "azapi_resource" "hub" {
  type      = "Microsoft.MachineLearningServices/workspaces@2024-10-01"
  name      = var.hub_name
  location  = var.location
  parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  tags      = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.user_assigned_identity_id]
  }

  body = {
    kind = "Hub"
    properties = {
      friendlyName                = var.hub_name
      storageAccount              = azurerm_storage_account.ai.id
      keyVault                    = var.key_vault_id
      applicationInsights         = var.app_insights_id
      primaryUserAssignedIdentity = var.user_assigned_identity_id
    }
    sku = {
      name = "Basic"
      tier = "Basic"
    }
  }

  depends_on = [
    azurerm_role_assignment.uai_storage_access,
    azurerm_role_assignment.uai_cognitive_services_user,
    azurerm_role_assignment.uai_cognitive_services_user_general
  ]
}

resource "azapi_resource" "ai_services_connection" {
  type      = "Microsoft.MachineLearningServices/workspaces/connections@2024-10-01"
  name      = "ai-services-connection"
  parent_id = azapi_resource.hub.id

  timeouts {
    create = "30m"
    delete = "60m" # Add this
  }

  body = {
    properties = {
      category      = "AIServices"
      target        = azurerm_cognitive_account.ai_services.endpoint
      authType      = "AAD"
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_cognitive_account.ai_services.id
      }
    }
  }
}

resource "azapi_resource" "project" {
  type      = "Microsoft.MachineLearningServices/workspaces@2024-10-01"
  name      = var.project_name
  location  = var.location
  parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  tags      = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.user_assigned_identity_id]
  }

  body = {
    kind = "Project"
    properties = {
      friendlyName                = var.project_name
      hubResourceId               = azapi_resource.hub.id
      primaryUserAssignedIdentity = var.user_assigned_identity_id
    }
    sku = {
      name = "Basic"
      tier = "Basic"
    }
  }

  depends_on = [azapi_resource.hub]
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
    private_dns_zone_ids = [var.ai_services_dns_zone_id]
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "storage_blob" {
  name                = "pe-st-${var.storage_account_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "storage-blob-connection"
    private_connection_resource_id = azurerm_storage_account.ai.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-st-${var.storage_account_name}"
    private_dns_zone_ids = [var.storage_dns_zone_id]
  }

  tags = var.tags
}

data "azurerm_client_config" "current" {}
