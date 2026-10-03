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

variable "public_network_access_enabled" {
  type = bool
}

variable "network_security_group_rules_required" {
  type = string
}

variable "no_public_ip" {
  type = bool
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "vnet_id" {
  type = string
}

variable "vnet_location" {
  type = string
}

variable "public_network_security_group_id" {
  type = string
}

variable "private_network_security_group_id" {
  type = string
}