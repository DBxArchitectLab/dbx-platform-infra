include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "workspace" {
  config_path = "../workspace"

  mock_outputs = {
    workspace_id          = 1234567890123456
    workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Databricks/workspaces/mock"
    workspace_url         = "https://adb-1234567890123456.7.azuredatabricks.net"
    workspace_name        = "dbw-dbx-architect-lab-prod"
  }

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

locals {
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  config = local.env.locals.config

  secret_scope_config      = yamldecode(file("${get_terragrunt_dir()}/secret-scope-config.yaml"))
  adls_config              = yamldecode(file("${get_terragrunt_dir()}/adls-storage-config.yaml"))
  access_connector_config  = yamldecode(file("${get_terragrunt_dir()}/access-connector-config.yaml"))
  catalog_config           = yamldecode(file("${get_terragrunt_dir()}/catalog-config.yaml"))
  external_location_config = yamldecode(file("${get_terragrunt_dir()}/external-location-config.yaml"))

  # Service principal that runs the deployment (application ID). It's added to the catalog and
  # external location grants so Terraform keeps the access it needs to manage them.
  deploy_sp_application_id = get_env("DEPLOY_SP_APPLICATION_ID")
}

terraform {
  source = "../../../modules/workspace_bootstrap"
}

inputs = merge(
  local.env.inputs,
  {
    databricks_host       = dependency.workspace.outputs.workspace_url
    workspace_resource_id = dependency.workspace.outputs.workspace_resource_id

    region              = local.config.region
    resource_group_name = local.config.resource_group_name

    storage_account_name     = local.adls_config.storage_account.name
    container_name           = local.adls_config.storage_account.container_name
    account_tier             = try(local.adls_config.storage_account.account_tier, "Standard")
    account_replication_type = try(local.adls_config.storage_account.account_replication_type, "LRS")

    access_connector_name = local.access_connector_config.access_connector.name

    catalog_name             = local.catalog_config.catalog.name
    catalog_managed_prefix   = try(local.catalog_config.catalog.managed_prefix, "managed")
    enable_catalog_grants    = try(local.catalog_config.catalog.enable_grants, true)
    catalog_grant_principals = distinct(concat(local.catalog_config.catalog.grant_principals, [local.deploy_sp_application_id]))
    catalog_grant_privileges = try(local.catalog_config.catalog.grant_privileges, [
      "BROWSE",
      "USE_CATALOG",
      "CREATE_SCHEMA",
    ])

    external_location_name  = local.external_location_config.external_location.name
    storage_credential_name = try(local.external_location_config.external_location.storage_credential_name, null)

    manage_access_connector_storage_rbac = try(local.external_location_config.external_location.manage_access_connector_storage_rbac, true)
    enable_external_location_grants      = try(local.external_location_config.external_location.enable_grants, true)
    external_location_owner              = try(local.external_location_config.external_location.owner, null)
    external_location_grant_principals   = distinct(concat(local.external_location_config.external_location.grant_principals, [local.deploy_sp_application_id]))
    external_location_grant_privileges = try(local.external_location_config.external_location.grant_privileges, [
      "MANAGE",
      "READ_FILES",
      "WRITE_FILES",
      "CREATE_EXTERNAL_TABLE",
    ])

    secret_scope_name = local.secret_scope_config.secret_scope.name

    default_tags = merge(
      try(local.config.tags, {}),
      {
        Layer     = "workspace-bootstrap"
        Workspace = dependency.workspace.outputs.workspace_name
      }
    )

    cluster_policy_config_file = "${get_terragrunt_dir()}/cluster-policy-config.yaml"
    cluster_config_file        = "${get_terragrunt_dir()}/cluster-config.yaml"
    sql_warehouse_config_file  = "${get_terragrunt_dir()}/sql-warehouse-config.yaml"
  }
)
