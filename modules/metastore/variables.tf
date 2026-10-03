variable "subscription_id" {
  type = string
}

variable "databricks_account_id" {
  type = string
}

variable "metastore_name" {
  type = string
}

variable "region" {
  type        = string
  description = "Cloud region for the metastore (e.g. eastus)."
}

variable "storage_root" {
  type        = string
  description = "ADLS Gen2 abfss:// URI used as the metastore root."
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Allow Terraform to delete the metastore even if it is not empty."
}

variable "owner" {
  type        = string
  default     = null
  description = "Optional Unity Catalog owner for the metastore."
}

variable "metastore_data_access_name" {
  type        = string
  default     = "default"
  description = "Name for the default metastore data access configuration when using an access connector."
}

variable "access_connector_resource_id" {
  type        = string
  default     = null
  description = "Azure Databricks Access Connector Azure resource ID for default managed identity data access. Leave null to skip databricks_metastore_data_access."
}
