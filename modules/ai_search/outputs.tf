output "id" {
  description = "Azure AI Search service resource ID"
  value       = azurerm_search_service.this.id
}

output "name" {
  description = "Azure AI Search service name"
  value       = azurerm_search_service.this.name
}

output "primary_key" {
  description = "Primary admin key"
  value       = azurerm_search_service.this.primary_key
  sensitive   = true
}

output "secondary_key" {
  description = "Secondary admin key"
  value       = azurerm_search_service.this.secondary_key
  sensitive   = true
}

output "query_keys" {
  description = "Query keys"
  value       = azurerm_search_service.this.query_keys
  sensitive   = true
}