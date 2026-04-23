output "ai_services_id" {
  description = "AI Services account resource ID"
  value       = azurerm_cognitive_account.ai_services.id
}

output "storage_account_id" {
  description = "Storage account resource ID used by AI Foundry"
  value       = var.storage_account_id
}

output "ai_services_endpoint" {
  description = "AI Services account endpoint"
  value       = azurerm_cognitive_account.ai_services.endpoint
}
