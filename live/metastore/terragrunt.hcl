include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env    = read_terragrunt_config("${get_terragrunt_dir()}/env.hcl")
  config = local.env.locals.config
}

terraform {
  source = "../../modules/metastore"
}

inputs = merge(
  local.env.inputs,
  {
    metastore_name               = local.config.metastore.name
    region                       = local.config.metastore.region
    storage_root                 = local.config.metastore.storage_root
    force_destroy                = try(local.config.metastore.force_destroy, false)
    owner                        = try(local.config.metastore.owner, null)
    metastore_data_access_name   = try(local.config.metastore.data_access_name, "default")
    access_connector_resource_id = try(local.config.metastore.access_connector_resource_id, null)
  }
)
