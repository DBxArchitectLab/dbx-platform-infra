output "private_endpoint_ids" {
  value = {
    ui      = azurerm_private_endpoint.ui.id
    auth    = azurerm_private_endpoint.auth.id
    backend = azurerm_private_endpoint.backend.id
  }
}

output "private_dns_zone_id" {
  value = local.private_dns_zone_id
}

output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "vnet_location" {
  value = azurerm_virtual_network.this.location
}

output "public_network_security_group_id" {
  value = azurerm_subnet_network_security_group_association.public.id
}

output "private_network_security_group_id" {
  value = azurerm_subnet_network_security_group_association.private.id
}