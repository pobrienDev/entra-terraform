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

output "ci_client_id" {
  description = "Client ID for the GitHub Actions identity (set as the AZURE_CLIENT_ID secret)."
  value       = azuread_application.ci.client_id
}

output "credmon_client_id" {
  description = "Client ID for the credential monitor's GitHub Actions identity (its AZURE_CLIENT_ID repository variable)."
  value       = azuread_application.credmon.client_id
}

output "ca_plan_client_id" {
  description = "Client ID for entra-conditional-access's read-only plan/drift identity (its CA_PLAN_CLIENT_ID secret)."
  value       = azuread_application.ca["plan"].client_id
}

output "ca_apply_client_id" {
  description = "Client ID for entra-conditional-access's apply identity (its CA_APPLY_CLIENT_ID secret, used only in the production environment)."
  value       = azuread_application.ca["apply"].client_id
}
