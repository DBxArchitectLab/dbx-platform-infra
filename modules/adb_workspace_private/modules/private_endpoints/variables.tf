variable "resource_group_name" {
  type = string
}

variable "region" {
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
}

variable "private_dns_zone_name" {
  type = string
}

variable "private_dns_zone_resource_group_name" {
  type    = string
  default = null
}

variable "workspace_resource_id" {
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