output "id" {
  description = "User Assigned Identity resource ID"
  value       = azurerm_user_assigned_identity.this.id
}

output "principal_id" {
  description = "User Assigned Identity principal ID"
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "client_id" {
  description = "User Assigned Identity client ID"
  value       = azurerm_user_assigned_identity.this.client_id
}

output "tenant_id" {
  description = "User Assigned Identity tenant ID"
  value       = azurerm_user_assigned_identity.this.tenant_id
}
