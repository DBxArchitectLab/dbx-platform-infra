variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "storage_account_name" {
  type        = string
  description = "Globally unique name (3–24 lowercase letters and numbers)."
}

variable "container_name" {
  type = string
}

variable "account_tier" {
  type    = string
  default = "Standard"
}

variable "account_replication_type" {
  type    = string
  default = "LRS"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the storage account."
}
