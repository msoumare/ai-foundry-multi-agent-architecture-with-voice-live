terraform {
  required_providers {
    azapi = {
      source = "azure/azapi"
    }
  }
}

resource "azapi_resource" "this" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2026-03-01"
  name      = var.name
  parent_id = var.ai_services_account_id
  location  = var.location
  tags      = var.tags

  # Keep schema validation disabled because this is a newly introduced resource type
  # and azapi schemas may lag behind public API versions.
  schema_validation_enabled = false

  body = {
    properties = {
      displayName = var.display_name
      description = var.description
    }
  }
}
