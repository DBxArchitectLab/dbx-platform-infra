provider "databricks" {
  host = var.databricks_host

  # Use Azure CLI authentication for local, user-based workflows.
  # Requires 'az login' with a user that has access to the workspace.
  azure_workspace_resource_id = var.workspace_resource_id
  auth_type                   = "azure-cli"
}

module "adls_storage" {
  source = "./modules/adls-storage"

  resource_group_name      = var.resource_group_name
  location                 = var.region
  storage_account_name     = var.storage_account_name
  container_name           = var.container_name
  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type
  tags                     = var.default_tags
}

module "access_connector" {
  source = "./modules/access-connector"

  name                = var.access_connector_name
  resource_group_name = var.resource_group_name
  location            = var.region
  tags                = var.default_tags
}

module "external_location" {
  source = "./modules/databricks-external-location"

  external_location_name               = var.external_location_name
  storage_account_name                 = module.adls_storage.storage_account_name
  storage_account_resource_group_name  = var.resource_group_name
  storage_container_name               = module.adls_storage.container_name
  storage_credential_name              = coalesce(var.storage_credential_name, "${var.external_location_name}_cred")
  access_connector_id                  = module.access_connector.access_connector_id
  access_connector_principal_id        = module.access_connector.principal_id
  manage_access_connector_storage_rbac = var.manage_access_connector_storage_rbac
  enable_external_location_grants      = var.enable_external_location_grants
  external_location_grant_principals   = var.external_location_grant_principals
  external_location_grant_privileges   = var.external_location_grant_privileges
  external_location_owner              = var.external_location_owner

  depends_on = [module.adls_storage, module.access_connector]
}

module "unity_catalog" {
  source = "./modules/databricks-unity-catalog"

  catalog_name             = var.catalog_name
  storage_account_name     = module.adls_storage.storage_account_name
  storage_container_name   = module.adls_storage.container_name
  catalog_managed_prefix   = var.catalog_managed_prefix
  enable_catalog_grants    = var.enable_catalog_grants
  catalog_grant_principals = var.catalog_grant_principals
  catalog_grant_privileges = var.catalog_grant_privileges

  depends_on = [module.external_location]
}

module "cluster_policy" {
  source = "./modules/databricks-cluster-policy"

  cluster_policies = local.cluster_policies
}

#module "cluster" {
#  source = "./modules/databricks-cluster"
#
#  clusters           = local.clusters
#  cluster_policy_ids = module.cluster_policy.cluster_policy_ids
#  default_tags       = var.default_tags
#}
#
#module "sql_warehouse" {
#  source = "./modules/databricks-sql-warehouse"
#
#  sql_warehouses = local.sql_warehouses
#  default_tags   = var.default_tags
#}

module "secret_scope" {
  source = "./modules/databricks-secret-scope"

  secret_scope_name = var.secret_scope_name
}
