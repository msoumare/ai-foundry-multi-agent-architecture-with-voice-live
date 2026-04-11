output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "aks_kube_config_command" {
  description = "Command to get AKS credentials"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${module.aks.cluster_name}"
}

output "acr_login_server" {
  description = "ACR login server URL"
  value       = module.acr.login_server
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = module.keyvault.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = module.keyvault.vault_uri
}

output "cosmos_db_endpoint" {
  description = "Cosmos DB account endpoint"
  value       = module.cosmosdb.endpoint
}

output "cosmos_db_database_name" {
  description = "Cosmos DB database name"
  value       = module.cosmosdb.database_name
}

output "redis_hostname" {
  description = "Redis Cache hostname"
  value       = module.redis.hostname
}

output "redis_port" {
  description = "Redis Cache SSL port"
  value       = module.redis.ssl_port
}

output "ai_search_name" {
  description = "Azure AI Search service name"
  value       = module.ai_search.name
}

output "ai_search_id" {
  description = "Azure AI Search service resource ID"
  value       = module.ai_search.id
}

output "vnet_id" {
  description = "Virtual network resource ID"
  value       = module.vnet.id
}

output "vnet_name" {
  description = "Virtual network name"
  value       = module.vnet.name
}

output "aks_subnet_id" {
  description = "AKS subnet resource ID"
  value       = module.vnet.aks_subnet_id
}

output "private_endpoints_subnet_id" {
  description = "Private endpoints subnet resource ID"
  value       = module.vnet.private_endpoints_subnet_id
}

output "app_insights_connection_string" {
  description = "Application Insights connection string"
  value       = module.monitoring.app_insights_connection_string
  sensitive   = true
}

output "ai_foundry_hub_name" {
  description = "AI Foundry Hub name"
  value       = module.ai_foundry.hub_name
}

output "ai_foundry_project_name" {
  description = "AI Foundry Project name"
  value       = module.ai_foundry.project_name
}

output "managed_identity_client_id" {
  description = "Client ID of the User Assigned Managed Identity"
  value       = module.identity.client_id
}
