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

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.workload.name
  address_prefixes     = var.bastion_subnet_prefixes
}

resource "azurerm_subnet" "dns_resolver_inbound" {
  name                 = "snet-dnsr-in-${var.workload}-${var.env}-${var.region}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.workload.name
  address_prefixes     = var.dns_resolver_subnet_prefixes

  delegation {
    name = "dnsResolverDelegation"

    service_delegation {
      name = "Microsoft.Network/dnsResolvers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_private_dns_resolver" "workload" {
  name                = "dnsr-${var.workload}-${var.env}-${var.region}"
  location            = var.location
  resource_group_name = var.resource_group_name
  virtual_network_id  = azurerm_virtual_network.workload.id
  tags                = var.tags
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "workload" {
  name                    = "dnsr-in-${var.workload}-${var.env}-${var.region}"
  location                = var.location
  private_dns_resolver_id = azurerm_private_dns_resolver.workload.id
  tags                    = var.tags

  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id                    = azurerm_subnet.dns_resolver_inbound.id
  }
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

# NAT Gateway for DevOps subnet egress
resource "azurerm_public_ip" "nat_gateway" {
  name                = "pip-nat-${var.workload}-${var.env}-${var.region}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "devops" {
  name                = "nat-${var.workload}-${var.env}-${var.region}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "devops" {
  nat_gateway_id       = azurerm_nat_gateway.devops.id
  public_ip_address_id = azurerm_public_ip.nat_gateway.id
}

resource "azurerm_subnet_nat_gateway_association" "devops" {
  subnet_id      = azurerm_subnet.workload_devops.id
  nat_gateway_id = azurerm_nat_gateway.devops.id
}