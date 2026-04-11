resource "azurerm_search_service" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  tags                = var.tags
}

resource "azurerm_search_service_shared_private_link" "ai_foundry" {
  name               = "spl-ai-foundry"
  search_service_id  = azurerm_search_service.this.id
  subresource_name   = "searchService"
  target_resource_id = var.ai_foundry_hub_id
  request_message    = "Private link for AI Foundry"
}