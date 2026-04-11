resource "azurerm_user_assigned_identity" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Key Vault Secrets User
resource "azurerm_role_assignment" "kv_secrets_user" {
  count               = var.key_vault_id != "" ? 1 : 0
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
}

# ACR Pull
resource "azurerm_role_assignment" "acr_pull" {
  count               = var.acr_id != "" ? 1 : 0
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
}

# Cognitive Services User
resource "azurerm_role_assignment" "cognitive_services_user" {
  count               = var.ai_services_id != "" ? 1 : 0
  scope                = var.ai_services_id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
}

# Cosmos DB Built-in Data Contributor
resource "azurerm_cosmosdb_sql_role_assignment" "data_contributor" {
  count              = var.cosmos_db_account_id != "" ? 1 : 0
  resource_group_name = var.resource_group_name
  account_name        = split("/", var.cosmos_db_account_id)[8]
  role_definition_id  = "${var.cosmos_db_account_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azurerm_user_assigned_identity.this.principal_id
  scope               = var.cosmos_db_account_id
}

# Storage Blob Data Contributor
resource "azurerm_role_assignment" "storage_blob_contributor" {
  count               = var.storage_account_id != "" ? 1 : 0
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
}

# --- Azure AI Search Contributor ---
resource "azurerm_role_assignment" "ai_search_contributor" {
  count               = var.ai_search_id != "" ? 1 : 0
  scope                = var.ai_search_id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
}
