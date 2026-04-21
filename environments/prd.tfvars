environment             = "prd"
workload                = "agenthubspoke"
region                  = "ne"
location                = "northeurope"
resource_group_workload = "rg-agenthubspoke-prd-ne"
log_analytics_workspace = "log-agenthubspoke-prd-ne"
subscription_id         = "3c9d7b7f-4666-43a3-a852-062c5b18c783"

address_space                     = ["10.1.0.0/16"]
aks_subnet_prefixes               = ["10.1.1.0/24"]
private_endpoints_subnet_prefixes = ["10.1.2.0/24"]
devops_subnet_prefixes            = ["10.1.3.0/24"]
bastion_subnet_prefixes           = ["10.1.4.0/26"]

enable_p2s_vpn               = true
gateway_subnet_prefixes      = ["10.1.5.0/27"]
dns_resolver_subnet_prefixes = ["10.1.6.0/28"]
p2s_vpn_client_address_space = ["172.16.20.0/24"]