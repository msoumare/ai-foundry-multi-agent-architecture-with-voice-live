data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.workload}-${var.environment}-${var.region}"
  location = var.location
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Virtual Network ---
module "vnet" {
  source = "./modules/vnet"

  name                              = "vnet-${var.workload}-${var.environment}-${var.region}"
  location                          = var.location
  resource_group_name               = azurerm_resource_group.main.name
  workload                          = var.workload
  env                               = var.environment
  # Keep legacy naming suffix aligned with existing deployed resources to avoid forced subnet replacement.
  # Remember to change the region to var.region for new deployments to other regions.
  region                            = var.location
  address_space                     = var.address_space
  aks_subnet_prefixes               = var.aks_subnet_prefixes
  private_endpoints_subnet_prefixes = var.private_endpoints_subnet_prefixes
  devops_subnet_prefixes            = var.devops_subnet_prefixes
  bastion_subnet_prefixes           = var.bastion_subnet_prefixes
  dns_resolver_subnet_prefixes      = var.dns_resolver_subnet_prefixes
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Point-to-Site VPN (Optional) ---
module "p2s_vpn" {
  count = var.enable_p2s_vpn ? 1 : 0

  source = "./modules/p2s_vpn"

  workload                     = var.workload
  env                          = var.environment
  region                       = var.region
  location                     = var.location
  resource_group_name          = azurerm_resource_group.main.name
  virtual_network_name         = module.vnet.name
  gateway_subnet_prefixes      = var.gateway_subnet_prefixes
  p2s_vpn_client_address_space = var.p2s_vpn_client_address_space
  p2s_dns_servers              = [module.vnet.private_dns_resolver_inbound_ip]
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Azure Bastion ---
resource "azurerm_public_ip" "bastion" {
  name                = "pip-bastion-${var.workload}-${var.environment}-${var.region}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

resource "azurerm_bastion_host" "main" {
  name                   = "bas-${var.workload}-${var.environment}-${var.region}"
  location               = var.location
  resource_group_name    = azurerm_resource_group.main.name
  sku                    = "Standard"
  copy_paste_enabled     = true
  file_copy_enabled      = false
  ip_connect_enabled     = true
  shareable_link_enabled = false
  tunneling_enabled      = true

  ip_configuration {
    name                 = "bastion-ipconfig"
    subnet_id            = module.vnet.bastion_subnet_id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }

  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Key Vault ---
module "keyvault" {
  source = "./modules/keyvault"

  name                = substr("akv-${var.workload}-${var.environment}-${var.region}", 0, 24)
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  private_endpoint_subnet_id = module.vnet.private_endpoints_subnet_id
  keyvault_dns_zone_id       = module.vnet.keyvault_dns_zone_id
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Key Vault RBAC: Secrets Officer for deploying principal ---
resource "azurerm_role_assignment" "deployer_kv_secrets_officer" {
  scope                = module.keyvault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# --- SSH Key for DevOps VMSS ---
resource "tls_private_key" "devops" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_key_vault_secret" "devops_ssh_private_key" {
  name         = "devops-ssh-private-key-${var.workload}-${var.environment}-${var.region}"
  value        = tls_private_key.devops.private_key_pem
  key_vault_id = module.keyvault.id

  depends_on = [azurerm_role_assignment.deployer_kv_secrets_officer]
}

# --- DevOps Identity (Minimal) ---
module "devops_identity" {
  source = "./modules/devops_identity"

  name                = "id-devops-${var.workload}-${var.environment}-${var.region}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  key_vault_id        = module.keyvault.id
  acr_id              = module.acr.id
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- DevOps VMSS (Build Agent) ---
module "devops" {
  source = "./modules/devops"

  name                = "vmss-devops-${var.workload}-${var.environment}-${var.region}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.vnet.devops_subnet_id
  admin_username      = "build_agent_user"
  ssh_public_key      = tls_private_key.devops.public_key_openssh
  identity_ids        = [module.devops_identity.id]
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Monitoring ---
module "monitoring" {
  source = "./modules/monitoring"

  name                       = "la-${var.workload}-${var.environment}-${var.region}"
  app_insights_name          = "appi-${var.workload}-${var.environment}-${var.region}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  private_endpoint_subnet_id = module.vnet.private_endpoints_subnet_id
  log_analytics_dns_zone_id  = module.vnet.log_analytics_dns_zone_id
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Container Registry ---
module "acr" {
  source = "./modules/acr"

  name                       = "acr${var.workload}${var.environment}${var.region}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  private_endpoint_subnet_id = module.vnet.private_endpoints_subnet_id
  acr_dns_zone_id            = module.vnet.acr_dns_zone_id
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Cosmos DB ---
module "cosmosdb" {
  source = "./modules/cosmosdb"

  name                       = "cosmos-${var.workload}-${var.environment}-${var.region}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  database_name              = var.cosmos_database_name
  container_name             = var.cosmos_container_name
  private_endpoint_subnet_id = module.vnet.private_endpoints_subnet_id
  cosmosdb_dns_zone_id       = module.vnet.cosmosdb_dns_zone_id
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Redis Cache ---
module "redis" {
  source = "./modules/redis"

  name                       = "redis-${var.workload}-${var.environment}-${var.region}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  sku_name                   = var.redis_sku_name
  family                     = var.redis_family
  capacity                   = var.redis_capacity
  private_endpoint_subnet_id = module.vnet.private_endpoints_subnet_id
  redis_dns_zone_id          = module.vnet.redis_dns_zone_id
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Foundry Identity (AI Foundry agents) ---
module "ai_foundry_identity" {
  source = "./modules/ai_foundry_identity"

  name                = "id-foundry-${var.workload}-${var.environment}-${var.region}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  key_vault_id        = module.keyvault.id
  storage_account_id  = module.storage.id
  ai_search_id        = module.ai_search.id
  cosmos_db_account_id = module.cosmosdb.id
  app_insights_id     = module.monitoring.app_insights_id
  ai_services_id      = module.ai_foundry.ai_services_id
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })

  depends_on = [module.ai_foundry]
}

# --- AI Foundry Storage ---
module "storage" {
  source = "./modules/storage"

  name                       = lower(substr("st${var.workload}${var.environment}${var.region}", 0, 24))
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  private_endpoint_subnet_id = module.vnet.private_endpoints_subnet_id
  storage_dns_zone_id        = module.vnet.storage_dns_zone_id
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- AI Foundry (AI Services) ---
module "ai_foundry" {
  source = "./modules/ai_foundry"

  ai_services_name           = "ai-${var.workload}-${var.environment}-${var.region}"
  storage_account_id         = module.storage.id
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  private_endpoint_subnet_id = module.vnet.private_endpoints_subnet_id
  ai_services_dns_zone_id    = module.vnet.ai_services_dns_zone_id
  ai_openai_dns_zone_id      = module.vnet.ai_openai_dns_zone_id
  ai_services_ai_dns_zone_id = module.vnet.ai_services_ai_dns_zone_id
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Foundry Project (new model: Cognitive Services projects) ---
module "ai_foundry_project" {
  source = "./modules/ai_foundry_project"

  name                   = "proj-${var.workload}-${var.environment}-${var.region}"
  display_name           = "proj-${var.workload}-${var.environment}-${var.region}"
  description            = "Foundry project for ${var.workload} ${var.environment} ${var.region}"
  location               = var.location
  ai_services_account_id = module.ai_foundry.ai_services_id
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- AI Real-Time (Voice Live API, Sweden Central) ---
module "ai_realtime" {
  source = "./modules/ai_realtime"

  ai_services_name    = "ai-rt-${var.workload}-${var.environment}-${var.region}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Azure AI Search ---
module "ai_search" {
  source = "./modules/ai_search"

  name                       = "search-${var.workload}-${var.environment}-${var.region}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  sku                        = "basic"
  private_endpoint_subnet_id = module.vnet.private_endpoints_subnet_id
  search_dns_zone_id         = module.vnet.search_dns_zone_id
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- AKS Compute Identity ---
module "aks_identity" {
  source = "./modules/aks_identity"

  name                      = "id-aks-${var.workload}-${var.environment}-${var.region}"
  location                  = var.location
  resource_group_name       = azurerm_resource_group.main.name
  key_vault_id              = module.keyvault.id
  acr_id                    = module.acr.id
  cosmos_db_account_id      = module.cosmosdb.id
  redis_id                  = module.redis.id
  ai_search_id              = module.ai_search.id
  foundry_ai_services_id    = module.ai_foundry.ai_services_id
  realtime_ai_services_id   = module.ai_realtime.ai_realtime_id
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- AKS ---
module "aks" {
  source = "./modules/aks"

  name                       = "aks-${var.workload}-${var.environment}-${var.region}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  user_assigned_identity_id  = module.aks_identity.id
  system_node_vm_size        = var.aks_system_node_vm_size
  user_node_vm_size          = var.aks_user_node_vm_size
  user_node_count            = var.aks_user_node_count
  vnet_subnet_id             = module.vnet.aks_subnet_id
  private_cluster_enabled    = true
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- ACR Pull role for AKS kubelet identity ---
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = module.acr.id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_identity_object_id
  principal_type       = "ServicePrincipal"
}
