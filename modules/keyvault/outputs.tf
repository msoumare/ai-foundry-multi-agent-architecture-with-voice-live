output "id" {
  description = "Key Vault resource ID"
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "Key Vault name"
  value       = azurerm_key_vault.this.name
}

output "vault_uri" {
  description = "Key Vault URI"
  value       = azurerm_key_vault.this.vault_uri
}

output "devops_ssh_public_key" {
  description = "Public key for the DevOps VMSS SSH key"
  value       = try(tls_private_key.devops[0].public_key_openssh, null)
}
