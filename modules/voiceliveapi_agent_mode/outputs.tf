output "ai_realtime_id" {
  description = "AI Services resource ID for Foundry-native Agent Mode Voice Live"
  value       = azurerm_cognitive_account.ai_realtime.id
}

output "ai_realtime_endpoint" {
  description = "AI Services endpoint for Foundry-native Agent Mode Voice Live"
  value       = azurerm_cognitive_account.ai_realtime.endpoint
}

output "ai_realtime_ws_endpoint" {
  description = "Voice Live websocket endpoint for agent mode"
  value       = "wss://${lower(replace(azurerm_cognitive_account.ai_realtime.location, " ", ""))}.tts.speech.microsoft.com/cognitiveservices/v1"
}
