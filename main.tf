# Configure the Microsoft Azure Provider
provider "azurerm" {
    # subscription_id = "00000000-0000-0000-0000-000000000000"
    # client_id = "00000000-0000-0000-0000-000000000000"
    # client_secret = "00000000-0000-0000-0000-000000000000"
    # tenant_id = "00000000-0000-0000-0000-000000000000"
}
# Create a resource group if it doesn’t exist
resource "azurerm_resource_group" "rg" {
    name = "cds-terraform"
    location = "westus"
}
# Create an Event Hubs namespace
resource "azurerm_eventhub_namespace" "eventhub" {
    name = "cds-terraform-eventhub-namespace"
    location = "${azurerm_resource_group.rg.location}"
    resource_group_name = "${azurerm_resource_group.rg.name}"
    sku = "Standard"
    capacity = 1

    tags = {
        environment = "Production"
    }
}
# Create an Event Hubs
resource "azurerm_eventhub" "eventhub" {
    name = "cds-terraform-eventhub"
    namespace_name = "${azurerm_eventhub_namespace.eventhub.name}"
    resource_group_name = "${azurerm_resource_group.rg.name}"
    partition_count = 3
    message_retention = 1
}
resource "azurerm_eventhub_authorization_rule" "eventhubpublisher" {
    name = "data-pump"
    namespace_name = "${azurerm_eventhub_namespace.eventhub.name}"
    resource_group_name = "${azurerm_resource_group.rg.name}"
    eventhub_name = "${azurerm_eventhub.eventhub.name}"
    listen = false
    send = true
    manage = false
}
resource "azurerm_eventhub_authorization_rule" "eventhubconsumer" {
    name = "replication-service"
    namespace_name = "${azurerm_eventhub_namespace.eventhub.name}"
    resource_group_name = "${azurerm_resource_group.rg.name}"
    eventhub_name = "${azurerm_eventhub.eventhub.name}"
    listen = true
    send = false
    manage = false
}
# Create an Azure SQL server for PostgreSQL
resource "random_password" "dbpassword" {
    length = 16
    special = true
    override_special = "_%@"
}
module "postgresql" {
  source              = "Azure/postgresql/azurerm"

    resource_group_name = "${azurerm_resource_group.rg.name}"
    location            = "${azurerm_resource_group.rg.location}"

    server_name = "cdsterraform"
    sku_name = "GP_Gen5_2"
    sku_capacity = 2
    sku_tier = "GeneralPurpose"
    sku_family = "Gen5"

    storage_mb = 5120
    backup_retention_days = 7
    geo_redundant_backup = "Disabled"

    administrator_login = "cdsterraform"
    administrator_password = "${random_password.dbpassword.result}"

    server_version = "9.5"
    ssl_enforcement = "Enabled"

    db_names = ["customer", "deliveryaddress", "pbl"]
    db_charset = "UTF8"
    db_collation = "English_United States.1252"

    firewall_rule_prefix = "firewall-"
    firewall_rules = [
        {name="cds-terraform", start_ip="0.0.0.0", end_ip="0.0.0.0"},
    ]
}
# Create a Service Principal to be register in AKS
module "service-principal" {
    source  = "innovationnorway/service-principal/azuread"
    version = "2.0.1"
  
    name = "cds-terraform-aks-service-principal"
}
# Create an AKS
resource "azurerm_kubernetes_cluster" "aks" {
    name = "cds-terraform-aks"
    location = "${azurerm_resource_group.rg.location}"
    resource_group_name = "${azurerm_resource_group.rg.name}"
    dns_prefix = "cdsterraform"

    default_node_pool {
        name = "default"
        node_count = 1
        vm_size = "Standard_D2_v2"
    }

    service_principal {
        client_id = "${module.service-principal.client_id}"
        client_secret = "${module.service-principal.client_secret}"
    }

    tags = {
        environment = "Production"
    }
}
output "client_certificate" {
    value = "${azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate}"
}
output "kube_config" {
  value = "${azurerm_kubernetes_cluster.aks.kube_config_raw}"
}




