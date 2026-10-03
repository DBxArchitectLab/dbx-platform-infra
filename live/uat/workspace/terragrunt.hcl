include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  config = local.env.locals.config
}

terraform {
  source = "../../../modules/adb_workspace_private"
}

inputs = merge(
  local.env.inputs,
  {
    resource_group_name         = local.config.resource_group_name
    workspace_name              = local.config.workspace_name
    region                      = local.config.region
    pricing_tier                = local.config.pricing_tier
    managed_resource_group_name = local.config.managed_resource_group_name

    vnet_name               = local.config.network.vnet_name
    public_subnet_name      = local.config.network.public_subnet_name
    private_subnet_name     = local.config.network.private_subnet_name
    privatelink_subnet_name = local.config.network.privatelink_subnet_name

    vnet_cidr               = local.config.network.vnet_cidr
    public_subnet_cidr      = local.config.network.public_subnet_cidr
    private_subnet_cidr     = local.config.network.private_subnet_cidr
    privatelink_subnet_cidr = local.config.network.privatelink_subnet_cidr

    public_network_access_enabled         = local.config.network.public_network_access_enabled
    network_security_group_rules_required = local.config.network.network_security_group_rules_required
    no_public_ip                          = local.config.network.no_public_ip

    private_endpoint_ui_name      = local.config.private_endpoints.ui_name
    private_endpoint_auth_name    = local.config.private_endpoints.auth_name
    private_endpoint_backend_name = local.config.private_endpoints.backend_name

    private_dns_zone_mode                = local.config.private_dns.mode
    private_dns_zone_name                = local.config.private_dns.name
    private_dns_zone_resource_group_name = local.config.private_dns.resource_group_name

    metastore_id              = get_env("DATABRICKS_METASTORE_ID")
    platform_admin_group_name = local.config.identity.platform_admin_group_name

    tags = local.config.tags
  }
)
