# Read-only identity for entra-credential-monitor (github.com/pobrienDev/entra-credential-monitor):
# a daily scan of app registration secrets, certificates and SAML signing
# certificates that runs in GitHub Actions.
#
# Like `ci` this app has no client secret at all. GitHub mints an OIDC token
# for the monitor's `monitor` environment and Entra ID trusts it via the
# federated credential below. The monitor's whole point is finding expiring
# secrets; its own identity is deliberately one that can't expire.

resource "azuread_application" "credmon" {
  display_name     = "credmon-reader"
  sign_in_audience = "AzureADMyOrg"
  owners           = [local.admin_object_id]

  required_resource_access {
    resource_app_id = data.azuread_service_principal.msgraph.client_id

    dynamic "resource_access" {
      for_each = toset(var.credmon_graph_app_roles)

      content {
        id   = data.azuread_service_principal.msgraph.app_role_ids[resource_access.value]
        type = "Role"
      }
    }
  }
}

resource "azuread_service_principal" "credmon" {
  client_id = azuread_application.credmon.client_id
  owners    = [local.admin_object_id]
}

# Trusts only jobs that run in the monitor repo's `monitor` environment, using
# the immutable owner@id/repo@id subject format (see ci.tf for why).
resource "azuread_application_federated_identity_credential" "credmon_github" {
  application_id = azuread_application.credmon.id
  display_name   = "github-actions-monitor"
  description    = "Daily credential scan from GitHub Actions"
  issuer         = "https://token.actions.githubusercontent.com"
  audiences      = ["api://AzureADTokenExchange"]
  subject        = var.credmon_github_oidc_subject
}

# Admin consent, one assignment per permission. Application.Read.All is the
# narrowest permission that lists applications and service principals with
# their credential metadata; User.ReadBasic.All only resolves owner names.
resource "azuread_app_role_assignment" "credmon_graph" {
  for_each = toset(var.credmon_graph_app_roles)

  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids[each.value]
  principal_object_id = azuread_service_principal.credmon.object_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}
