output "hub_id" {
  description = "AI Foundry Hub resource ID"
  value       = azapi_resource.hub.id
}

output "hub_name" {
  description = "AI Foundry Hub name"
  value       = azapi_resource.hub.name
}

output "project_id" {
  description = "AI Foundry Project resource ID"
  value       = azapi_resource.project.id
}

output "project_name" {
  description = "AI Foundry Project name"
  value       = azapi_resource.project.name
}

output "ai_services_id" {
  description = "AI Services account resource ID"
  value       = azurerm_cognitive_account.ai_services.id
}

output "ai_services_endpoint" {
  description = "AI Services account endpoint"
  value       = azurerm_cognitive_account.ai_services.endpoint
}

output "storage_account_id" {
  description = "Storage account resource ID"
  value       = azurerm_storage_account.ai.id
}
