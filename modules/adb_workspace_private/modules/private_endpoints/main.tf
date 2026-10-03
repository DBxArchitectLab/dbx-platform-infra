/*
data "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name
}

data "azurerm_subnet" "privatelink" {
  name                 = var.privatelink_subnet_name
  virtual_network_name = data.azurerm_virtual_network.this.name
  resource_group_name  = var.resource_group_name
}
*/

resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  location            = var.region
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_cidr
  tags                = var.tags
}

resource "azurerm_network_security_group" "this" {
  name                = "${var.vnet_name}-nsg"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet" "public" {
  name                 = var.public_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.public_subnet_cidr

  delegation {
    name = "databricks"
    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
      "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.this.id
}

resource "azurerm_subnet" "private" {
  name                 = var.private_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.private_subnet_cidr

  delegation {
    name = "databricks"
    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
      "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = azurerm_subnet.private.id
  network_security_group_id = azurerm_network_security_group.this.id
}

resource "azurerm_subnet" "privatelink" {
  name                 = var.privatelink_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.privatelink_subnet_cidr
}

resource "azurerm_subnet_network_security_group_association" "privatelink" {
  subnet_id                 = azurerm_subnet.privatelink.id
  network_security_group_id = azurerm_network_security_group.this.id
}

locals {
  create_private_dns_zone = lower(var.private_dns_zone_mode) == "create"

  dns_zone_rg_name = coalesce(
    var.private_dns_zone_resource_group_name,
    var.resource_group_name
  )
}

resource "azurerm_private_dns_zone" "databricks" {
  count               = local.create_private_dns_zone ? 1 : 0
  name                = var.private_dns_zone_name
  resource_group_name = local.dns_zone_rg_name
  tags                = var.tags
}

data "azurerm_private_dns_zone" "databricks" {
  count               = local.create_private_dns_zone ? 0 : 1
  name                = var.private_dns_zone_name
  resource_group_name = local.dns_zone_rg_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "databricks" {
  name                  = "${var.vnet_name}-adb-plink"
  resource_group_name   = local.dns_zone_rg_name
  private_dns_zone_name = local.create_private_dns_zone ? azurerm_private_dns_zone.databricks[0].name : data.azurerm_private_dns_zone.databricks[0].name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}

locals {
  private_dns_zone_id = local.create_private_dns_zone ? azurerm_private_dns_zone.databricks[0].id : data.azurerm_private_dns_zone.databricks[0].id
}

resource "azurerm_private_endpoint" "ui" {
  name                = var.private_endpoint_ui_name
  location            = var.region
  resource_group_name = var.resource_group_name
  subnet_id           = azurerm_subnet.privatelink.id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.private_endpoint_ui_name}-psc"
    private_connection_resource_id = var.workspace_resource_id
    subresource_names              = ["databricks_ui_api"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.private_dns_zone_id]
  }

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.databricks
  ]
}

resource "azurerm_private_endpoint" "auth" {
  name                = var.private_endpoint_auth_name
  location            = var.region
  resource_group_name = var.resource_group_name
  subnet_id           = azurerm_subnet.privatelink.id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.private_endpoint_auth_name}-psc"
    private_connection_resource_id = var.workspace_resource_id
    subresource_names              = ["browser_authentication"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.private_dns_zone_id]
  }

  depends_on = [
    azurerm_private_endpoint.ui
  ]
}

resource "azurerm_private_endpoint" "backend" {
  name                = var.private_endpoint_backend_name
  location            = var.region
  resource_group_name = var.resource_group_name
  subnet_id           = azurerm_subnet.privatelink.id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.private_endpoint_backend_name}-psc"
    private_connection_resource_id = var.workspace_resource_id
    subresource_names              = ["databricks_ui_api"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.private_dns_zone_id]
  }

  depends_on = [
    azurerm_private_endpoint.auth
  ]
}