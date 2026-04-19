resource "azurerm_container_registry" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Premium"
  admin_enabled       = false
  public_network_access_enabled = false
  tags                = var.tags
}

resource "azurerm_private_endpoint" "this" {
  name                = "pe-acr-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "acr-connection"
    private_connection_resource_id = azurerm_container_registry.this.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-acr-${var.name}"
    private_dns_zone_ids = [var.acr_dns_zone_id]
  }

  tags = var.tags
}
