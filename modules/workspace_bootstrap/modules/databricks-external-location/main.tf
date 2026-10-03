data "azurerm_storage_account" "this" {
  name                = var.storage_account_name
  resource_group_name = var.storage_account_resource_group_name
}

data "azurerm_storage_container" "this" {
  name                 = var.storage_container_name
  storage_account_name = data.azurerm_storage_account.this.name
}

locals {
  external_url = "abfss://${data.azurerm_storage_container.this.name}@${data.azurerm_storage_account.this.name}.dfs.core.windows.net/"
  # Unity Catalog owners can manage the object; without this, grant-only MANAGE may apply after EL updates in the same run and Terraform still fails to modify the location.
  external_location_owner = coalesce(var.external_location_owner, var.external_location_grant_principals[0])
}

# Unity Catalog validates the credential against ADLS using the connector's managed identity.
# That identity must have data-plane RBAC on the storage account (Storage Blob Data Contributor).
resource "azurerm_role_assignment" "access_connector_storage_blob_data_contributor" {
  count                = var.manage_access_connector_storage_rbac && var.access_connector_principal_id != null ? 1 : 0
  scope                = data.azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.access_connector_principal_id
  principal_type       = "ServicePrincipal"
}

resource "databricks_storage_credential" "this" {
  name = var.storage_credential_name

  # Required when the credential is bound to external locations (Unity Catalog API otherwise rejects in-place updates).
  force_update = true

  azure_managed_identity {
    access_connector_id = var.access_connector_id
  }

  lifecycle {
    precondition {
      condition     = var.access_connector_id != null && var.access_connector_id != ""
      error_message = "access_connector_id must be set to the Azure resource ID of a Databricks access connector."
    }
  }

  depends_on = [azurerm_role_assignment.access_connector_storage_blob_data_contributor]
}

resource "databricks_external_location" "this" {
  name            = var.external_location_name
  url             = local.external_url
  credential_name = databricks_storage_credential.this.name
  comment         = "Bootstrap external location."
  owner           = local.external_location_owner
  force_update    = true
}

resource "databricks_grants" "external_location" {
  count = var.enable_external_location_grants ? 1 : 0

  external_location = databricks_external_location.this.name

  dynamic "grant" {
    for_each = toset(var.external_location_grant_principals)
    content {
      principal  = grant.value
      privileges = var.external_location_grant_privileges
    }
  }

  depends_on = [databricks_external_location.this]
}
