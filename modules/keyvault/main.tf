data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                          = var.name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  soft_delete_retention_days    = 7
  purge_protection_enabled      = true
  enable_rbac_authorization     = true
  public_network_access_enabled = true
  tags                          = var.tags
}

# --- Key Vault RBAC: Secrets Officer for deploying principal ---
resource "azurerm_role_assignment" "deployer_kv_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# --- SSH Key for DevOps VMSS ---
resource "tls_private_key" "devops" {
  count     = var.devops_ssh_private_key_secret_name == "" ? 0 : 1
  algorithm = "RSA"
  rsa_bits  = 4096

  lifecycle {
    ignore_changes = all
  }
}

resource "azurerm_key_vault_secret" "devops_ssh_private_key" {
  count        = var.devops_ssh_private_key_secret_name == "" ? 0 : 1
  name         = var.devops_ssh_private_key_secret_name
  value        = tls_private_key.devops[0].private_key_pem
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [azurerm_role_assignment.deployer_kv_secrets_officer]
}

resource "azurerm_private_endpoint" "this" {
  name                = "pe-kv-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  
  private_service_connection {
    name                           = "keyvault-connection"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-kv-${var.name}"
    private_dns_zone_ids = [var.keyvault_dns_zone_id]
  }

  tags = var.tags
}
