data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

/*
data "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name
}

data "azurerm_subnet" "public" {
  name                 = var.public_subnet_name
  virtual_network_name = data.azurerm_virtual_network.this.name
  resource_group_name  = var.resource_group_name
}

data "azurerm_subnet" "private" {
  name                 = var.private_subnet_name
  virtual_network_name = data.azurerm_virtual_network.this.name
  resource_group_name  = var.resource_group_name
}
*/

resource "azurerm_databricks_workspace" "this" {
  name                                  = var.workspace_name
  resource_group_name                   = data.azurerm_resource_group.this.name
  location                              = var.region
  sku                                   = var.pricing_tier
  managed_resource_group_name           = var.managed_resource_group_name
  public_network_access_enabled         = var.public_network_access_enabled
  network_security_group_rules_required = var.network_security_group_rules_required
  tags                                  = var.tags

  custom_parameters {
    no_public_ip = var.no_public_ip

    virtual_network_id  = var.vnet_id             # data.azurerm_virtual_network.this.id
    public_subnet_name  = var.public_subnet_name  # data.azurerm_subnet.public.name
    private_subnet_name = var.private_subnet_name # data.azurerm_subnet.private.name

    public_subnet_network_security_group_association_id  = var.public_network_security_group_id  # data.azurerm_subnet.public.network_security_group_id
    private_subnet_network_security_group_association_id = var.private_network_security_group_id # data.azurerm_subnet.private.network_security_group_id
  }

  lifecycle {
    precondition {
      condition     = lower(var.pricing_tier) == "premium"
      error_message = "This design requires Premium SKU."
    }

    precondition {
      condition     = var.no_public_ip == true
      error_message = "no_public_ip must be true."
    }

    precondition {
      condition     = lower(var.network_security_group_rules_required) == "noazuredatabricksrules"
      error_message = "network_security_group_rules_required must be NoAzureDatabricksRules."
    }

    precondition {
      # data.azurerm_virtual_network.this.location
      condition     = lower(var.vnet_location) == lower(var.region)
      error_message = "VNet and workspace must be in the same region."
    }
  }
}