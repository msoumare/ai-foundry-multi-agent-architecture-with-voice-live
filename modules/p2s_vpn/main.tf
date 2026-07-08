data "azurerm_client_config" "current" {}

locals {
  # Keep zone-redundant public IP where supported, but omit zones in regions
  # that do not support zonal Public IPs for this resource type.
  zonal_public_ip_locations = [
    "northeurope",
    "eastus",
    "swedencentral",
  ]
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.virtual_network_name
  address_prefixes     = var.gateway_subnet_prefixes
}

resource "azurerm_public_ip" "vpn_gateway" {
  name                = "pip-vpngw-${var.workload}-${var.env}-${var.region}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = contains(local.zonal_public_ip_locations, lower(replace(var.location, " ", ""))) ? ["1", "2", "3"] : null
  tags                = var.tags

  # This IP is attached to the VPN gateway and should never be replaced by incidental drift.
  # Ignoring all changes avoids destructive replacement attempts that fail while attached.
  lifecycle {
    ignore_changes = all
  }
}

resource "azurerm_virtual_network_gateway" "p2s" {
  name                = "vpngw-${var.workload}-${var.env}-${var.region}"
  location            = var.location
  resource_group_name = var.resource_group_name

  type     = "Vpn"
  vpn_type = "RouteBased"
  # Azure now requires AZ SKUs for new VPN gateways (VpnGw1-5).
  # Keep AZ SKU regardless of region; Public IP zones are still region-conditional above.
  sku = "VpnGw1AZ"

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

  tags = var.tags

  # Gateway deployment can take a long time and occasionally needs extra provisioning window.
  timeouts {
    create = "90m"
    update = "90m"
    delete = "90m"
  }
}
