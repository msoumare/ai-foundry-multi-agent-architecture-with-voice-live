environment             = "dev"
workload                = "agenthubspoke"
region                  = "ne"
location                = "northeurope"
resource_group_workload = "rg-agenthubspoke-dev-ne"
log_analytics_workspace = "log-agenthubspoke-dev-ne"
subscription_id         = "3c9d7b7f-4666-43a3-a852-062c5b18c783"

address_space                    = ["10.0.0.0/16"]
aks_subnet_prefixes              = ["10.0.1.0/24"]
private_endpoints_subnet_prefixes = ["10.0.2.0/24"]
devops_subnet_prefixes           = ["10.0.3.0/24"]
bastion_subnet_prefixes          = ["10.0.4.0/26"]