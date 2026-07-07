output "traffic_controller_id" {
  description = "Resource ID of the Application Gateway for Containers traffic controller."
  value       = azapi_resource.traffic_controller.id
}

output "frontend_id" {
  description = "Resource ID of the Application Gateway for Containers frontend."
  value       = azapi_resource.frontend.id
}

output "association_id" {
  description = "Resource ID of the Application Gateway for Containers association."
  value       = azapi_resource.association.id
}
