variable "subscription_id" {
  type = string
}

variable "databricks_account_id" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "workspace_name" {
  type = string
}

variable "region" {
  type = string
}

variable "pricing_tier" {
  type = string

  validation {
    condition     = lower(var.pricing_tier) == "premium"
    error_message = "This module requires pricing_tier = premium."
  }
}

variable "managed_resource_group_name" {
  type = string
}

variable "vnet_name" {
  type = string
}

variable "public_subnet_name" {
  type = string
}

variable "private_subnet_name" {
  type = string
}

variable "privatelink_subnet_name" {
  type = string
}

variable "privatelink_subnet_cidr" {
  type = list(string)
}

variable "public_network_access_enabled" {
  type = bool
}

variable "network_security_group_rules_required" {
  type = string

  validation {
    condition     = contains(["AllRules", "NoAzureDatabricksRules"], var.network_security_group_rules_required)
    error_message = "network_security_group_rules_required must be AllRules or NoAzureDatabricksRules."
  }
}

variable "no_public_ip" {
  type = bool
}

variable "private_endpoint_ui_name" {
  type = string
}

variable "private_endpoint_auth_name" {
  type = string
}

variable "private_endpoint_backend_name" {
  type = string
}

variable "private_dns_zone_mode" {
  type = string

  validation {
    condition     = contains(["create", "existing"], lower(var.private_dns_zone_mode))
    error_message = "private_dns_zone_mode must be create or existing."
  }
}

variable "private_dns_zone_name" {
  type = string
}

variable "private_dns_zone_resource_group_name" {
  type    = string
  default = null
}

variable "metastore_id" {
  type = string
}

variable "platform_admin_group_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "vnet_cidr" {
  type = list(string)
}

variable "public_subnet_cidr" {
  type = list(string)
}

variable "private_subnet_cidr" {
  type = list(string)
}