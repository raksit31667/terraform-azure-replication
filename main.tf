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




