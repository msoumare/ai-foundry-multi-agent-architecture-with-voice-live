output "ai_realtime_id" {
  description = "AI Services resource ID (Sweden Central, Voice Live API)"
  value       = azurerm_cognitive_account.ai_realtime.id
}

output "ai_realtime_endpoint" {
  description = "AI Services endpoint for real-time voice"
  value       = azurerm_cognitive_account.ai_realtime.endpoint
}
