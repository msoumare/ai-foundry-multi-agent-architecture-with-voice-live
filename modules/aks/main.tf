resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.name
  tags                = var.tags

  default_node_pool {
    name                 = "system"
    node_count           = 1
    vm_size              = var.system_node_vm_size
    vnet_subnet_id       = var.vnet_subnet_id
    type                 = "VirtualMachineScaleSets"
    auto_scaling_enabled = false
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.user_assigned_identity_id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = "192.168.0.0/16"
    service_cidr        = "10.240.0.0/16"
    dns_service_ip      = "10.240.0.10"
  }

  private_cluster_enabled = var.private_cluster_enabled

  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.user_node_vm_size
  node_count            = var.user_node_count
  vnet_subnet_id        = var.vnet_subnet_id
  os_disk_size_gb       = 50
  tags                  = var.tags
}
