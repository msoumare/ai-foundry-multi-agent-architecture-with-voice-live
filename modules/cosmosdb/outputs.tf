output "id" {
  description = "Cosmos DB account resource ID"
  value       = azurerm_cosmosdb_account.this.id
}

output "name" {
  description = "Cosmos DB account name"
  value       = azurerm_cosmosdb_account.this.name
}

output "endpoint" {
  description = "Cosmos DB account endpoint"
  value       = azurerm_cosmosdb_account.this.endpoint
}

output "database_name" {
  description = "Cosmos DB SQL database name"
  value       = azurerm_cosmosdb_sql_database.this.name
}
