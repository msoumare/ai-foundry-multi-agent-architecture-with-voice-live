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

output "primary_access_key" {
  description = "Redis Cache primary access key"
  value       = azurerm_redis_cache.this.primary_access_key
  sensitive   = true
}

output "primary_connection_string" {
  description = "Redis Cache primary connection string"
  value       = azurerm_redis_cache.this.primary_connection_string
  sensitive   = true
}
