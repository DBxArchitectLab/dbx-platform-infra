output "external_location_name" {
  value = databricks_external_location.this.name
}

output "external_location_url" {
  value = databricks_external_location.this.url
}

output "storage_credential_name" {
  value = databricks_storage_credential.this.name
}

output "access_connector_principal_id" {
  description = "Object (principal) ID of the access connector managed identity — use for manual Storage Blob Data Contributor assignment when manage_access_connector_storage_rbac is false."
  value       = var.access_connector_principal_id
}
