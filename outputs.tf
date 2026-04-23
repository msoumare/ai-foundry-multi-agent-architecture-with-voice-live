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

output "bastion_subnet_id" {
  description = "Azure Bastion subnet resource ID"
  value       = module.vnet.bastion_subnet_id
}

output "bastion_host_name" {
  description = "Azure Bastion host name"
  value       = azurerm_bastion_host.main.name
}

output "bastion_public_ip" {
  description = "Azure Bastion public IP address"
  value       = azurerm_public_ip.bastion.ip_address
}

output "devops_ssh_private_key_secret_name" {
  description = "Key Vault secret name containing the DevOps VMSS SSH private key"
  value       = azurerm_key_vault_secret.devops_ssh_private_key.name
}

output "app_insights_connection_string" {
  description = "Application Insights connection string"
  value       = module.monitoring.app_insights_connection_string
  sensitive   = true
}

output "ai_foundry_identity_client_id" {
  description = "Client ID of the Foundry User Assigned Identity"
  value       = module.ai_foundry_identity.client_id
}

output "p2s_vpn_gateway_id" {
  description = "Point-to-Site VPN gateway resource ID"
  value       = var.enable_p2s_vpn ? module.p2s_vpn[0].vpn_gateway_id : null
}

output "p2s_vpn_gateway_public_ip" {
  description = "Point-to-Site VPN gateway public IP address"
  value       = var.enable_p2s_vpn ? module.p2s_vpn[0].vpn_gateway_public_ip : null
}

output "ai_realtime_endpoint" {
  description = "AI Services endpoint for Voice Live API (gpt-realtime, Sweden Central)"
  value       = module.ai_realtime.ai_realtime_endpoint
}

