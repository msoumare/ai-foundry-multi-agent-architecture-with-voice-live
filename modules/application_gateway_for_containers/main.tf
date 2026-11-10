terraform {
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
  }
}

resource "azapi_resource" "traffic_controller" {
  type      = "Microsoft.ServiceNetworking/trafficControllers@2025-03-01-preview"
  name      = var.name
  parent_id = var.resource_group_id
  location  = var.location
  tags      = var.tags

  body = {
    properties = {}
  }
}

resource "azapi_resource" "frontend" {
  type      = "Microsoft.ServiceNetworking/trafficControllers/frontends@2025-03-01-preview"
  name      = var.frontend_name
  parent_id = azapi_resource.traffic_controller.id
  location  = var.location
  tags      = var.tags

  body = {
    properties = {}
  }
}

resource "azapi_resource" "association" {
  type      = "Microsoft.ServiceNetworking/trafficControllers/associations@2025-03-01-preview"
  name      = var.association_name
  parent_id = azapi_resource.traffic_controller.id
  location  = var.location
  tags      = var.tags

  body = {
    properties = {
      associationType = "subnets"
      subnet = {
        id = var.association_subnet_id
      }
    }
  }
}
