resource "azurerm_user_assigned_identity" "foundry" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}


# Key Vault Secrets User — for Foundry agents to access secrets and API keys
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.foundry.principal_id
  principal_type       = "ServicePrincipal"
}

# Storage Blob Data Contributor — for Foundry artifacts, models, and datasets
resource "azurerm_role_assignment" "storage_blob_data_contributor" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.foundry.principal_id
  principal_type       = "ServicePrincipal"
}

# ACR repository pull access for hosted agent images
resource "azurerm_role_assignment" "acr_repository_reader" {
  scope                = var.acr_id
  role_definition_name = "Container Registry Repository Reader"
  principal_id         = var.foundry_project_principal_id
  principal_type       = "ServicePrincipal"
}

# Azure AI Search data plane — for RAG and knowledge index retrieval
resource "azurerm_role_assignment" "ai_search_contributor" {
  scope                = var.ai_search_id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azurerm_user_assigned_identity.foundry.principal_id
  principal_type       = "ServicePrincipal"
}

# Azure AI Search management plane — for index/resource management workflows
resource "azurerm_role_assignment" "ai_search_service_contributor" {
  scope                = var.ai_search_id
  role_definition_name = "Search Service Contributor"
  principal_id         = azurerm_user_assigned_identity.foundry.principal_id
  principal_type       = "ServicePrincipal"
}

# Cosmos DB Built-in Data Contributor — for agents to access conversation history and state
resource "azurerm_cosmosdb_sql_role_assignment" "cosmos_data_contributor" {
  resource_group_name = var.resource_group_name
  account_name        = split("/", var.cosmos_db_account_id)[8]
  role_definition_id  = "${var.cosmos_db_account_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azurerm_user_assigned_identity.foundry.principal_id
  scope               = var.cosmos_db_account_id
}

# Monitoring Contributor — for Application Insights telemetry and tracing
resource "azurerm_role_assignment" "monitoring_contributor" {
  scope                = var.app_insights_id
  role_definition_name = "Monitoring Contributor"
  principal_id         = azurerm_user_assigned_identity.foundry.principal_id
  principal_type       = "ServicePrincipal"
}

# Cognitive Services User — general access to AI Services account
resource "azurerm_role_assignment" "cognitive_services_user" {
  scope                = var.ai_services_id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_user_assigned_identity.foundry.principal_id
  principal_type       = "ServicePrincipal"
}

# Cognitive Services OpenAI User — for inference on GPT deployments
resource "azurerm_role_assignment" "cognitive_services_openai_user" {
  scope                = var.ai_services_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.foundry.principal_id
  principal_type       = "ServicePrincipal"
}
