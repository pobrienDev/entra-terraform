# The identity the Python automation tools authenticate as (client-credentials
# flow): an app registration, its service principal, and admin-consented
# Microsoft Graph application permissions.

data "azuread_client_config" "current" {}

# Microsoft Graph's app ID and permission IDs are looked up by name rather
# than hardcoded as GUIDs, so the permission list below stays readable.
data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]
}

locals {
  graph_app_roles = toset(concat(
    var.graph_app_roles,
    var.enable_credential_reset ? var.credential_reset_app_roles : [],
  ))
}

resource "azuread_application" "automation" {
  display_name     = "${var.name_prefix}-graph-automation"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]

  # Declares which permissions the app *requests*. Declaring is not granting —
  # see azuread_app_role_assignment below.
  required_resource_access {
    resource_app_id = data.azuread_service_principal.msgraph.client_id

    dynamic "resource_access" {
      for_each = local.graph_app_roles

      content {
        id   = data.azuread_service_principal.msgraph.app_role_ids[resource_access.value]
        type = "Role" # application permission (app-only), not delegated "Scope"
      }
    }
  }
}

resource "azuread_service_principal" "automation" {
  client_id = azuread_application.automation.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# The code equivalent of clicking "Grant admin consent" in the portal: one
# assignment per permission, from Graph's service principal to ours.
resource "azuread_app_role_assignment" "graph" {
  for_each = local.graph_app_roles

  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids[each.value]
  principal_object_id = azuread_service_principal.automation.object_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}
