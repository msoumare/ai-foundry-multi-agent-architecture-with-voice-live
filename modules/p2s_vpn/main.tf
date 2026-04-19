data "azurerm_client_config" "current" {}

data "azurerm_virtual_network" "target" {
  name                = var.virtual_network_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.virtual_network_name
  address_prefixes     = var.gateway_subnet_prefixes
}

resource "azurerm_subnet" "dns_resolver_inbound" {
  name                 = "snet-dns-inbound-${var.workload}-${var.env}-${var.region}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.virtual_network_name
  address_prefixes     = var.dns_resolver_inbound_subnet_prefixes

  delegation {
    name = "dns-resolver-delegation"

    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_private_dns_resolver" "p2s" {
  name                = "dnspr-${var.workload}-${var.env}-${var.region}"
  location            = var.location
  resource_group_name = var.resource_group_name
  virtual_network_id  = data.azurerm_virtual_network.target.id
  tags                = var.tags
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "p2s" {
  name                    = "inbound-${var.workload}-${var.env}-${var.region}"
  private_dns_resolver_id = azurerm_private_dns_resolver.p2s.id
  location                = var.location
  tags                    = var.tags

  ip_configurations {
    private_ip_allocation_method = "Static"
    private_ip_address           = var.dns_resolver_inbound_ip
    subnet_id                    = azurerm_subnet.dns_resolver_inbound.id
  }
}

resource "azurerm_public_ip" "vpn_gateway" {
  name                = "pip-vpngw-${var.workload}-${var.env}-${var.region}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway" "p2s" {
  name                = "vpngw-${var.workload}-${var.env}-${var.region}"
  location            = var.location
  resource_group_name = var.resource_group_name

  type     = "Vpn"
  vpn_type = "RouteBased"
  sku      = "VpnGw1AZ"

  active_active = false
  enable_bgp    = false

  ip_configuration {
    name                          = "vpngw-ipconfig"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vpn_gateway.id
    subnet_id                     = azurerm_subnet.gateway.id
  }

  vpn_client_configuration {
    address_space = var.p2s_vpn_client_address_space

    vpn_client_protocols = ["OpenVPN"]
    vpn_auth_types       = ["AAD"]
    aad_tenant           = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/"
    aad_audience         = "c632b3df-fb67-4d84-bdcf-b95ad541b5c8"
    aad_issuer           = "https://sts.windows.net/${data.azurerm_client_config.current.tenant_id}/"
  }

  depends_on = [azurerm_private_dns_resolver_inbound_endpoint.p2s]

  tags = var.tags
}
