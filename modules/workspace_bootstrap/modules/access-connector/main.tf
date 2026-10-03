resource "azurerm_databricks_access_connector" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}
