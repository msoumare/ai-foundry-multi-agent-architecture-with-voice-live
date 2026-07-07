resource "azurerm_redis_cache" "this" {
  name                               = var.name
  location                           = var.location
  resource_group_name                = var.resource_group_name
  capacity                           = var.capacity
  family                             = var.family
  sku_name                           = var.sku_name
  access_keys_authentication_enabled = false
  minimum_tls_version                = "1.2"
  public_network_access_enabled      = false
  tags                               = var.tags

  redis_configuration {
    active_directory_authentication_enabled = true
  }
}

resource "azurerm_private_endpoint" "this" {
  name                = "pe-redis-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "redis-connection"
    private_connection_resource_id = azurerm_redis_cache.this.id
    subresource_names              = ["redisCache"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-redis-${var.name}"
    private_dns_zone_ids = [var.redis_dns_zone_id]
  }

  tags = var.tags
}
