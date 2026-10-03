variable "external_location_name" {
  description = "Unity Catalog external location name"
  type        = string
}

variable "external_location_owner" {
  description = "Unity Catalog owner (user, group, or service principal id). Defaults to the first entry in external_location_grant_principals. The Terraform identity should be this user, a member of this group, or metastore admin."
  type        = string
  nullable    = true
  default     = null
}

variable "storage_account_name" {
  description = "ADLS Gen2 storage account name"
  type        = string
}

variable "storage_account_resource_group_name" {
  description = "Resource group name of the storage account"
  type        = string
}

variable "storage_container_name" {
  description = "Storage container name for the external location root"
  type        = string
}

variable "storage_credential_name" {
  description = "Databricks storage credential name"
  type        = string
}

variable "access_connector_id" {
  description = "Azure resource ID of the Databricks access connector used for Unity Catalog storage credential"
  type        = string
}

variable "access_connector_principal_id" {
  description = "Object ID of the access connector managed identity (for optional Terraform-managed Storage Blob Data Contributor)"
  type        = string
  default     = null
}

variable "manage_access_connector_storage_rbac" {
  description = <<-EOT
    If true, Terraform creates role assignment "Storage Blob Data Contributor" for the access connector
    managed identity on the storage account. Requires the Terraform principal to have
    Microsoft.Authorization/roleAssignments/write (e.g. Owner or User Access Administrator on the scope).
    If false, grant that role manually (Azure Portal or CLI) before creating the external location.
  EOT
  type        = bool
  default     = true
}

variable "enable_external_location_grants" {
  description = "If true, apply databricks_grants on the external location for external_location_grant_principals."
  type        = bool
  default     = true
}

variable "external_location_grant_principals" {
  description = "Principals to receive privileges on the external location: group names, user emails, or service principal application IDs. The first entry is the default owner."
  type        = list(string)

  validation {
    condition     = length(var.external_location_grant_principals) > 0
    error_message = "external_location_grant_principals must contain at least one principal."
  }
}

variable "external_location_grant_privileges" {
  description = "Unity Catalog privileges for EXTERNAL_LOCATION. Include MANAGE so the grant principals (and the Terraform runner, if it is one of them or in one of those groups) can update the location; omit MANAGE in production if you restrict who may alter locations."
  type        = list(string)
  default = [
    "MANAGE",
    "READ_FILES",
    "WRITE_FILES",
    "CREATE_EXTERNAL_TABLE",
  ]
}
