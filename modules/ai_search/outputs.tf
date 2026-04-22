output "id" {
  description = "Azure AI Search service resource ID"
  value       = azurerm_search_service.this.id
}

output "name" {
  description = "Azure AI Search service name"
  value       = azurerm_search_service.this.name
}

output "endpoint" {
  description = "Azure AI Search endpoint"
  value       = azurerm_search_service.this.endpoint
}