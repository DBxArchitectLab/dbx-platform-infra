resource "databricks_metastore" "this" {
  provider = databricks.account

  name          = var.metastore_name
  storage_root  = var.storage_root
  region        = var.region
  force_destroy = var.force_destroy
  owner         = var.owner
}

resource "databricks_metastore_data_access" "default" {
  count = var.access_connector_resource_id != null && var.access_connector_resource_id != "" ? 1 : 0

  provider = databricks.account

  metastore_id = databricks_metastore.this.id
  name         = var.metastore_data_access_name

  azure_managed_identity {
    access_connector_id = var.access_connector_resource_id
  }

  is_default = true

  depends_on = [databricks_metastore.this]
}
