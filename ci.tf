# Identity that GitHub Actions uses to run `terraform plan` on pull requests.
#
# Separate from the automation app on purpose: it has no client secret at all.
# GitHub mints a short-lived OIDC token for each workflow run, and Entra ID
# trusts that token directly via the federated credentials below. Every role
# it holds is read-only, so CI can plan but can never apply.

resource "azuread_application" "ci" {
  display_name     = "${var.name_prefix}-github-plan"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]

  required_resource_access {
    resource_app_id = data.azuread_service_principal.msgraph.client_id

    resource_access {
      id   = data.azuread_service_principal.msgraph.app_role_ids["Application.Read.All"]
      type = "Role"
    }
  }
}

resource "azuread_service_principal" "ci" {
  client_id = azuread_application.ci.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# The `subject` must match the token's `sub` claim exactly — one character off
# and login fails with AADSTS700213. A token is only issued for workflows in
# this repository, and GitHub never issues one to pull requests from forks.
#
# This repo uses GitHub's immutable subject format, which embeds the numeric
# owner and repo IDs (repo:owner@123/name@456). Names can be re-registered by
# someone else after a rename or deletion; IDs can't, so trust can't be
# inherited by a look-alike repo.
locals {
  ci_subjects = {
    pull-request = "${var.github_oidc_subject_prefix}:pull_request"
    main-branch  = "${var.github_oidc_subject_prefix}:ref:refs/heads/main"
  }
}

resource "azuread_application_federated_identity_credential" "github" {
  for_each = local.ci_subjects

  application_id = azuread_application.ci.id
  display_name   = "github-${each.key}"
  description    = "GitHub Actions, ${var.github_repository} (${each.key})"
  issuer         = "https://token.actions.githubusercontent.com"
  audiences      = ["api://AzureADTokenExchange"]
  subject        = each.value
}

# --- Read-only access, one grant per thing `plan` has to refresh -------------

# Entra: read app registrations, service principals and permission grants.
resource "azuread_app_role_assignment" "ci_graph_read" {
  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids["Application.Read.All"]
  principal_object_id = azuread_service_principal.ci.object_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}

# Azure: management-plane read on the workload resource group.
resource "azurerm_role_assignment" "ci_reader" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.ci.object_id
}

# Refreshing azurerm_key_vault_secret reads the secret from the data plane.
# This does let CI read the client secret — but CI can already read state,
# which contains it. Anything that can plan this config can see that secret;
# the protection is who can obtain a token (this repo only, never forks).
resource "azurerm_role_assignment" "ci_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azuread_service_principal.ci.object_id
}

# State: read the blob. Reader, not Contributor — CI runs plan with
# -lock=false so it never needs to write a lease.
data "azurerm_storage_account" "tfstate" {
  name                = var.state_storage_account_name
  resource_group_name = var.state_resource_group_name
}

resource "azurerm_role_assignment" "ci_state_reader" {
  scope                = "${data.azurerm_storage_account.tfstate.id}/blobServices/default/containers/tfstate"
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azuread_service_principal.ci.object_id
}

# "Data Reader" covers blob contents only. Plain Reader on the same container
# lets CI refresh these two role assignments themselves, which live outside
# the workload resource group — scoped to the container, not the whole group.
resource "azurerm_role_assignment" "ci_state_container_reader" {
  scope                = "${data.azurerm_storage_account.tfstate.id}/blobServices/default/containers/tfstate"
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.ci.object_id
}
