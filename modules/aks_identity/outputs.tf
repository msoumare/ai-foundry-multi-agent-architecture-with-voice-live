output "id" {
  description = "AKS Identity resource ID"
  value       = azurerm_user_assigned_identity.this.id
}

output "principal_id" {
  description = "AKS Identity principal ID"
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "client_id" {
  description = "AKS Identity client ID"
  value       = azurerm_user_assigned_identity.this.client_id
}

output "tenant_id" {
  description = "AKS Identity tenant ID"
  value       = azurerm_user_assigned_identity.this.tenant_id
}
