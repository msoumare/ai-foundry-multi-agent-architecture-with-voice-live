output "id" {
  description = "Virtual network resource ID"
  value       = azurerm_virtual_network.workload.id
}

output "name" {
  description = "Virtual network name"
  value       = azurerm_virtual_network.workload.name
}

output "aks_subnet_id" {
  description = "AKS subnet resource ID"
  value       = azurerm_subnet.workload_aks.id
}

output "private_endpoints_subnet_id" {
  description = "Private endpoints subnet resource ID"
  value       = azurerm_subnet.workload_private_endpoints.id
}

output "devops_subnet_id" {
  description = "DevOps subnet resource ID"
  value       = azurerm_subnet.workload_devops.id
}

output "bastion_subnet_id" {
  description = "Azure Bastion subnet resource ID"
  value       = azurerm_subnet.bastion.id
}

output "alb_subnet_id" {
  description = "Application Gateway for Containers association subnet resource ID"
  value       = azurerm_subnet.alb.id
}

output "keyvault_dns_zone_id" {
  description = "Key Vault private DNS zone ID"
  value       = azurerm_private_dns_zone.keyvault.id
}

output "cosmosdb_dns_zone_id" {
  description = "Cosmos DB private DNS zone ID"
  value       = azurerm_private_dns_zone.cosmosdb.id
}

output "redis_dns_zone_id" {
  description = "Redis private DNS zone ID"
  value       = azurerm_private_dns_zone.redis.id
}

output "search_dns_zone_id" {
  description = "AI Search private DNS zone ID"
  value       = azurerm_private_dns_zone.search.id
}

output "storage_dns_zone_id" {
  description = "Storage private DNS zone ID"
  value       = azurerm_private_dns_zone.storage.id
}

output "acr_dns_zone_id" {
  description = "ACR private DNS zone ID"
  value       = azurerm_private_dns_zone.acr.id
}

output "ai_services_dns_zone_id" {
  description = "AI Services private DNS zone ID"
  value       = azurerm_private_dns_zone.ai_services.id
}

output "ai_openai_dns_zone_id" {
  description = "OpenAI private DNS zone ID"
  value       = azurerm_private_dns_zone.ai_openai.id
}

output "ai_services_ai_dns_zone_id" {
  description = "Services AI private DNS zone ID"
  value       = azurerm_private_dns_zone.ai_services_ai.id
}

output "log_analytics_dns_zone_id" {
  description = "Log Analytics private DNS zone ID"
  value       = azurerm_private_dns_zone.log_analytics.id
}

output "nat_gateway_id" {
  description = "NAT Gateway resource ID"
  value       = azurerm_nat_gateway.devops.id
}

output "nat_gateway_public_ip" {
  description = "NAT Gateway public IP address"
  value       = azurerm_public_ip.nat_gateway.ip_address
}

output "private_dns_resolver_id" {
  description = "Private DNS Resolver resource ID"
  value       = azurerm_private_dns_resolver.workload.id
}

output "private_dns_resolver_inbound_ip" {
  description = "Private DNS Resolver inbound endpoint IP address"
  value       = azurerm_private_dns_resolver_inbound_endpoint.workload.ip_configurations[0].private_ip_address
}