output "ai_realtime_agent_mode_id" {
  description = "AI Services resource ID for Foundry-native Agent Mode Voice Live"
  value       = azurerm_cognitive_account.ai_realtime_agent_mode.id
}

output "ai_realtime_agent_mode_endpoint" {
  description = "AI Services endpoint for Foundry-native Agent Mode Voice Live"
  value       = azurerm_cognitive_account.ai_realtime_agent_mode.endpoint
}
