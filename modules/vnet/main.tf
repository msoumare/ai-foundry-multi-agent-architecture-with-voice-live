resource "azurerm_virtual_network" "workload" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  tags                = var.tags
}

resource "azurerm_subnet" "workload_aks" {
  name                 = "snet-aks-${var.workload}-${var.env}-${var.region}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.workload.name
  address_prefixes     = var.aks_subnet_prefixes
}

resource "azurerm_subnet" "workload_private_endpoints" {
  name                 = "snet-pe-${var.workload}-${var.env}-${var.region}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.workload.name
  address_prefixes     = var.private_endpoints_subnet_prefixes
}

resource "azurerm_subnet" "workload_devops" {
  name                 = "snet-devops-${var.workload}-${var.env}-${var.region}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.workload.name
  address_prefixes     = var.devops_subnet_prefixes
}

# Private DNS Zones
resource "azurerm_private_dns_zone" "keyvault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "cosmosdb" {
  name                = "privatelink.documents.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "redis" {
  name                = "privatelink.redis.cache.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "search" {
  name                = "privatelink.search.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "storage" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "ai_services" {
  name                = "privatelink.cognitiveservices.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "log_analytics" {
  name                = "privatelink.oms.opinsights.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Private DNS Zone Virtual Network Links
resource "azurerm_private_dns_zone_virtual_network_link" "keyvault" {
  name                  = "link-kv-${var.workload}-${var.env}-${var.region}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = azurerm_virtual_network.workload.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "cosmosdb" {
  name                  = "link-cosmos-${var.workload}-${var.env}-${var.region}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.cosmosdb.name
  virtual_network_id    = azurerm_virtual_network.workload.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "redis" {
  name                  = "link-redis-${var.workload}-${var.env}-${var.region}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.redis.name
  virtual_network_id    = azurerm_virtual_network.workload.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "search" {
  name                  = "link-search-${var.workload}-${var.env}-${var.region}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.search.name
  virtual_network_id    = azurerm_virtual_network.workload.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage" {
  name                  = "link-st-${var.workload}-${var.env}-${var.region}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.storage.name
  virtual_network_id    = azurerm_virtual_network.workload.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  name                  = "link-acr-${var.workload}-${var.env}-${var.region}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = azurerm_virtual_network.workload.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "ai_services" {
  name                  = "link-ais-${var.workload}-${var.env}-${var.region}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.ai_services.name
  virtual_network_id    = azurerm_virtual_network.workload.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "log_analytics" {
  name                  = "link-la-${var.workload}-${var.env}-${var.region}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.log_analytics.name
  virtual_network_id    = azurerm_virtual_network.workload.id
}