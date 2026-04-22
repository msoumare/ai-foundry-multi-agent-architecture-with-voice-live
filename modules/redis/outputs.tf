output "id" {
  description = "Redis Cache resource ID"
  value       = azurerm_redis_cache.this.id
}

output "name" {
  description = "Redis Cache name"
  value       = azurerm_redis_cache.this.name
}

output "hostname" {
  description = "Redis Cache hostname"
  value       = azurerm_redis_cache.this.hostname
}

output "ssl_port" {
  description = "Redis Cache SSL port"
  value       = azurerm_redis_cache.this.ssl_port
}
