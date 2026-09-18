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
