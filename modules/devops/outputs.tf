output "id" {
  description = "VMSS resource ID"
  value       = azurerm_orchestrated_virtual_machine_scale_set.devops.id
}

output "name" {
  description = "VMSS name"
  value       = azurerm_orchestrated_virtual_machine_scale_set.devops.name
}