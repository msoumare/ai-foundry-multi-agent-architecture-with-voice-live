output "id" {
  description = "Foundry project resource ID"
  value       = azapi_resource.this.id
}

output "name" {
  description = "Foundry project resource name"
  value       = azapi_resource.this.name
}
