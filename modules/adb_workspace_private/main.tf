module "private_endpoints" {
  source = "./modules/private_endpoints"

  resource_group_name                  = var.resource_group_name
  region                               = var.region
  vnet_name                            = var.vnet_name
  public_subnet_name                   = var.public_subnet_name
  private_subnet_name                  = var.private_subnet_name
  privatelink_subnet_name              = var.privatelink_subnet_name
  private_endpoint_ui_name             = var.private_endpoint_ui_name
  private_endpoint_auth_name           = var.private_endpoint_auth_name
  private_endpoint_backend_name        = var.private_endpoint_backend_name
  private_dns_zone_mode                = var.private_dns_zone_mode
  private_dns_zone_name                = var.private_dns_zone_name
  private_dns_zone_resource_group_name = var.private_dns_zone_resource_group_name
  privatelink_subnet_cidr              = var.privatelink_subnet_cidr
  workspace_resource_id                = module.workspace.workspace_resource_id
  tags                                 = var.tags
  vnet_cidr                            = var.vnet_cidr
  public_subnet_cidr                   = var.public_subnet_cidr
  private_subnet_cidr                  = var.private_subnet_cidr
}

module "workspace" {
  source = "./modules/workspace"

  resource_group_name                   = var.resource_group_name
  workspace_name                        = var.workspace_name
  region                                = var.region
  pricing_tier                          = var.pricing_tier
  managed_resource_group_name           = var.managed_resource_group_name
  vnet_name                             = var.vnet_name
  public_subnet_name                    = var.public_subnet_name
  private_subnet_name                   = var.private_subnet_name
  public_network_access_enabled         = var.public_network_access_enabled
  network_security_group_rules_required = var.network_security_group_rules_required
  no_public_ip                          = var.no_public_ip
  tags                                  = var.tags
  vnet_id                               = module.private_endpoints.vnet_id
  public_network_security_group_id      = module.private_endpoints.public_network_security_group_id
  private_network_security_group_id     = module.private_endpoints.private_network_security_group_id
  vnet_location                         = module.private_endpoints.vnet_location
}

module "metastore_assignment" {
  source = "./modules/metastore_assignment"

  providers = {
    databricks.account = databricks.account
  }

  workspace_id = module.workspace.workspace_id
  metastore_id = var.metastore_id
}

module "workspace_group_assignment" {
  source = "./modules/workspace_group_assignment"

  providers = {
    databricks.account = databricks.account
  }

  workspace_id              = module.workspace.workspace_id
  platform_admin_group_name = var.platform_admin_group_name
}