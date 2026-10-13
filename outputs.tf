output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "application_client_id" {
  description = "Client ID the automation tools authenticate with."
  value       = azuread_application.automation.client_id
}

output "granted_graph_permissions" {
  description = "Graph application permissions that were admin-consented."
  value       = sort(keys(azuread_app_role_assignment.graph))
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "client_secret_name" {
  description = "Name of the Key Vault secret holding the client secret. The value itself is deliberately not an output."
  value       = azurerm_key_vault_secret.client_secret.name
}

output "client_secret_expires" {
  value = time_rotating.client_secret.rotation_rfc3339
}

output "github_client_ids" {
  description = "Client IDs of the GitHub Actions identities. ci: this repo's AZURE_CLIENT_ID secret. credmon: entra-credential-monitor's AZURE_CLIENT_ID variable. ca-plan / ca-apply: entra-conditional-access's CA_PLAN_CLIENT_ID / CA_APPLY_CLIENT_ID secrets."
  value       = { for key, app in azuread_application.github : key => app.client_id }
}
