resource "azurerm_resource_group" "main" {
  name     = "rg-${var.workload}-${var.environment}-${var.location}"
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

  name                = "vnet-${var.workload}-${var.environment}-${var.location}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  workload            = var.workload
  env                 = var.environment
  region              = var.location
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Azure Bastion ---
resource "azurerm_public_ip" "bastion" {
  name                = "pip-bastion-${var.workload}-${var.environment}-${var.location}"
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
  name                = "bas-${var.workload}-${var.environment}-${var.location}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
  copy_paste_enabled  = true
  file_copy_enabled   = false
  ip_connect_enabled  = true
  shareable_link_enabled = false
  tunneling_enabled   = true

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

  name                = substr("kv-${var.workload}-${var.environment}-${var.location}", 0, 24)
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- SSH Key for DevOps VMSS ---
resource "tls_private_key" "devops" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_key_vault_secret" "devops_ssh_private_key" {
  name         = "devops-ssh-private-key-${var.workload}-${var.environment}-${var.location}"
  value        = tls_private_key.devops.private_key_pem
  key_vault_id = module.keyvault.id
}

# --- DevOps Identity (Minimal) ---
module "devops_identity" {
  source = "./modules/identity"

  name                = "id-devops-${var.workload}-${var.environment}-${var.location}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  key_vault_id        = module.keyvault.id
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- DevOps VMSS (Build Agent) ---
module "devops" {
  source = "./modules/devops"

  name                = "vmss-devops-${var.workload}-${var.environment}-${var.location}"
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

  name                = "la-${var.workload}-${var.environment}-${var.location}"
  app_insights_name   = "appi-${var.workload}-${var.environment}-${var.location}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Container Registry ---
module "acr" {
  source = "./modules/acr"

  name                = "acr-${var.workload}-${var.environment}-${var.location}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- ACR Private Endpoint ---
resource "azurerm_private_endpoint" "acr" {
  name                = "pe-acr-${var.workload}-${var.environment}-${var.location}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.vnet.private_endpoints_subnet_id

  private_service_connection {
    name                           = "acr-connection"
    private_connection_resource_id = module.acr.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-acr-${var.workload}-${var.environment}-${var.location}"
    private_dns_zone_ids = [module.vnet.acr_dns_zone_id]
  }

  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Cosmos DB ---
module "cosmosdb" {
  source = "./modules/cosmosdb"

  name                = "cosmos-${var.workload}-${var.environment}-${var.location}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  database_name       = var.cosmos_database_name
  container_name      = var.cosmos_container_name
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Cosmos DB Private Endpoint ---
resource "azurerm_private_endpoint" "cosmosdb" {
  name                = "pe-cosmos-${var.workload}-${var.environment}-${var.location}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.vnet.private_endpoints_subnet_id

  private_service_connection {
    name                           = "cosmosdb-connection"
    private_connection_resource_id = module.cosmosdb.id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-cosmos-${var.workload}-${var.environment}-${var.location}"
    private_dns_zone_ids = [module.vnet.cosmosdb_dns_zone_id]
  }

  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Redis Cache ---
module "redis" {
  source = "./modules/redis"

  name                = "redis-${var.workload}-${var.environment}-${var.location}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = var.redis_sku_name
  family              = var.redis_family
  capacity            = var.redis_capacity
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Redis Private Endpoint ---
resource "azurerm_private_endpoint" "redis" {
  name                = "pe-redis-${var.workload}-${var.environment}-${var.location}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.vnet.private_endpoints_subnet_id

  private_service_connection {
    name                           = "redis-connection"
    private_connection_resource_id = module.redis.id
    subresource_names              = ["redisCache"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-redis-${var.workload}-${var.environment}-${var.location}"
    private_dns_zone_ids = [module.vnet.redis_dns_zone_id]
  }

  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- AI Foundry (AI Services + Hub + Project + Storage) ---
module "ai_foundry" {
  source = "./modules/ai_foundry"

  hub_name             = "af-hub-${var.workload}-${var.environment}-${var.location}"
  project_name         = "af-proj-${var.workload}-${var.environment}-${var.location}"
  ai_services_name     = "ai-${var.workload}-${var.environment}-${var.location}"
  storage_account_name = substr(replace("st${var.workload}${var.environment}${var.location}", "-", ""), 0, 24)
  location             = var.location
  resource_group_name  = azurerm_resource_group.main.name
  key_vault_id         = module.keyvault.id
  app_insights_id      = module.monitoring.app_insights_id
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- AI Services Private Endpoint ---
resource "azurerm_private_endpoint" "ai_services" {
  name                = "pe-ai-${var.workload}-${var.environment}-${var.location}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.vnet.private_endpoints_subnet_id

  private_service_connection {
    name                           = "ai-services-connection"
    private_connection_resource_id = module.ai_foundry.ai_services_id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-ai-${var.workload}-${var.environment}-${var.location}"
    private_dns_zone_ids = [module.vnet.ai_services_dns_zone_id]
  }

  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Storage Account Private Endpoint ---
resource "azurerm_private_endpoint" "storage_blob" {
  name                = "pe-st-${var.workload}-${var.environment}-${var.location}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.vnet.private_endpoints_subnet_id

  private_service_connection {
    name                           = "storage-blob-connection"
    private_connection_resource_id = module.ai_foundry.storage_account_id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-st-${var.workload}-${var.environment}-${var.location}"
    private_dns_zone_ids = [module.vnet.storage_dns_zone_id]
  }

  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Azure AI Search ---
module "ai_search" {
  source = "./modules/ai_search"

  name                = "search-${var.workload}-${var.environment}-${var.location}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "basic"
  ai_foundry_hub_id   = module.ai_foundry.hub_id
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- AI Search Private Endpoint ---
resource "azurerm_private_endpoint" "ai_search" {
  name                = "pe-search-${var.workload}-${var.environment}-${var.location}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.vnet.private_endpoints_subnet_id

  private_service_connection {
    name                           = "ai-search-connection"
    private_connection_resource_id = module.ai_search.id
    subresource_names              = ["searchService"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-search-${var.workload}-${var.environment}-${var.location}"
    private_dns_zone_ids = [module.vnet.search_dns_zone_id]
  }

  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- Identity + RBAC ---
module "identity" {
  source = "./modules/identity"

  name                = "id-${var.workload}-${var.environment}-${var.location}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  key_vault_id        = module.keyvault.id
  acr_id              = module.acr.id
  cosmos_db_account_id = module.cosmosdb.id
  ai_services_id      = module.ai_foundry.ai_services_id
  storage_account_id  = module.ai_foundry.storage_account_id
  ai_search_id        = module.ai_search.id
  tags = merge(var.tags, {
    environment = var.environment
    workload    = var.workload
    managed-by  = "terraform"
  })
}

# --- AKS ---
module "aks" {
  source = "./modules/aks"

  name                       = "aks-${var.workload}-${var.environment}-${var.location}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  user_assigned_identity_id  = module.identity.id
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

# --- Log Analytics Private Endpoint ---
resource "azurerm_private_endpoint" "log_analytics" {
  name                = "pe-la-${var.workload}-${var.environment}-${var.location}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.vnet.private_endpoints_subnet_id

  private_service_connection {
    name                           = "log-analytics-connection"
    private_connection_resource_id = module.monitoring.log_analytics_workspace_id
    subresource_names              = ["azuremonitor"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-la-${var.workload}-${var.environment}-${var.location}"
    private_dns_zone_ids = [module.vnet.log_analytics_dns_zone_id]
  }

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
