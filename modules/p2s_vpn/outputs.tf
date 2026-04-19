output "gateway_subnet_id" {
  description = "GatewaySubnet resource ID"
  value       = azurerm_subnet.gateway.id
}

output "vpn_gateway_id" {
  description = "Point-to-Site VPN gateway resource ID"
  value       = azurerm_virtual_network_gateway.p2s.id
}

output "vpn_gateway_public_ip" {
  description = "Point-to-Site VPN gateway public IP address"
  value       = azurerm_public_ip.vpn_gateway.ip_address
}

output "dns_resolver_id" {
  description = "Azure DNS Private Resolver resource ID"
  value       = azurerm_private_dns_resolver.p2s.id
}

output "dns_resolver_inbound_ip" {
  description = "DNS Private Resolver inbound endpoint private IP"
  value       = var.dns_resolver_inbound_ip
}
