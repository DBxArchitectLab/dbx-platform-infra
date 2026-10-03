output "cluster_policy_ids" {
  value = module.cluster_policy.cluster_policy_ids
}

#output "cluster_ids" {
#  value = module.cluster.cluster_ids
#}
#
#output "sql_warehouse_ids" {
#  value = module.sql_warehouse.sql_warehouse_ids
#}

output "storage_account_name" {
  description = "ADLS Gen2 storage account created for Unity Catalog"
  value       = module.adls_storage.storage_account_name
}

output "storage_account_id" {
  value = module.adls_storage.storage_account_id
}

output "access_connector_id" {
  description = "Azure resource ID of the Databricks access connector"
  value       = module.access_connector.access_connector_id
}

output "unity_catalog_id" {
  value = module.unity_catalog.catalog_id
}

output "unity_catalog_name" {
  value = module.unity_catalog.catalog_name
}

output "unity_catalog_storage_root" {
  value = module.unity_catalog.catalog_storage_root
}

output "unity_catalog_external_location_name" {
  value = module.external_location.external_location_name
}

output "unity_catalog_external_location_url" {
  value = module.external_location.external_location_url
}

output "unity_catalog_storage_credential_name" {
  value = module.external_location.storage_credential_name
}

output "access_connector_principal_id" {
  description = "Access connector managed identity object id — grant Storage Blob Data Contributor on the ADLS account when RBAC is not managed by Terraform."
  value       = module.external_location.access_connector_principal_id
}

output "secret_scope_name" {
  value = module.secret_scope.secret_scope_name
}
