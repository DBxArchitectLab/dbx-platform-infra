variable "catalog_name" {
  description = "Unity Catalog catalog name to create"
  type        = string
}

variable "storage_account_name" {
  description = "ADLS Gen2 storage account used as managed storage root for the catalog"
  type        = string
}

variable "storage_container_name" {
  description = "Container name within the storage account for managed catalog data"
  type        = string
}

variable "catalog_managed_prefix" {
  description = "Path prefix inside the container for this catalog (avoids colliding with external location root)"
  type        = string
  default     = "managed"
}

variable "enable_catalog_grants" {
  description = "If true, grants Unity Catalog privileges on the catalog to catalog_grant_principals (needed for visibility in Data Explorer)."
  type        = bool
  default     = true
}

variable "catalog_grant_principals" {
  description = "Principals to receive privileges on the catalog: group names, user emails, or service principal application IDs."
  type        = list(string)

  validation {
    condition     = length(var.catalog_grant_principals) > 0
    error_message = "catalog_grant_principals must contain at least one principal."
  }
}

variable "catalog_grant_privileges" {
  description = "Catalog-level UC privileges only (BROWSE, USE_CATALOG, CREATE_SCHEMA). Table/view/volume privileges belong on SCHEMA, not CATALOG."
  type        = list(string)
  default = [
    "BROWSE",
    "USE_CATALOG",
    "CREATE_SCHEMA",
  ]
}
