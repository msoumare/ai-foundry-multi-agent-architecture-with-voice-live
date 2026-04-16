resource "azurerm_search_service" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  tags                = var.tags
}

# Shared private link removed — Azure Search does not support 'searchService' subresource_name as outbound type

resource "azurerm_private_endpoint" "this" {
  name                = "pe-search-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "ai-search-connection"
    private_connection_resource_id = azurerm_search_service.this.id
    subresource_names              = ["searchService"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-search-${var.name}"
    private_dns_zone_ids = [var.search_dns_zone_id]
  }

  tags = var.tags
}