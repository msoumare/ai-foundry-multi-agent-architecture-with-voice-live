output "id" {
  description = "User Assigned Identity resource ID"
  value       = azurerm_user_assigned_identity.foundry.id
}

output "principal_id" {
  description = "Principal ID (object ID) of the User Assigned Identity"
  value       = azurerm_user_assigned_identity.foundry.principal_id
}

output "client_id" {
  description = "Client ID of the User Assigned Identity"
  value       = azurerm_user_assigned_identity.foundry.client_id
}
