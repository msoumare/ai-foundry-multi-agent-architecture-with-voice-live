output "ai_services_id" {
  description = "AI Services account resource ID"
  value       = azurerm_cognitive_account.ai_services.id
}

output "ai_services_endpoint" {
  description = "AI Services account endpoint"
  value       = azurerm_cognitive_account.ai_services.endpoint
}
