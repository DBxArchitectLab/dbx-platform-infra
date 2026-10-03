output "access_connector_id" {
  description = "Azure resource ID of the access connector (for databricks_storage_credential)."
  value       = azurerm_databricks_access_connector.this.id
}

output "principal_id" {
  description = "Object ID of the access connector system-assigned managed identity (for Storage Blob Data Contributor)."
  value       = azurerm_databricks_access_connector.this.identity[0].principal_id
}
