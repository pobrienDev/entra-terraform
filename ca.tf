# Two identities for entra-conditional-access (github.com/pobrienDev/entra-conditional-access),
# which manages the tenant's Conditional Access policies as Terraform.
#
# App-only identities are not subject to Conditional Access, so an identity
# that can write CA policies could rewrite every policy in the tenant. That is
# why there are two, and why the write permission is only reachable through a
# GitHub environment that requires a human approval:
#
#   ca-plan   read-only   plans on pull requests and the daily drift check
#   ca-apply  read/write  applies after merge, only from the approval-gated
#                         `production` environment
#
# Like `ci` and `credmon`, neither has a client secret. GitHub mints an OIDC
# token per run and Entra ID trusts it via the federated credentials below,
# using the immutable owner@id/repo@id subject format (see ci.tf for why).

locals {
  ca_identities = {
    plan = {
      display_name = "ca-plan"
      description  = "Read-only: terraform plan on pull requests and daily drift detection"
      graph_roles  = var.ca_plan_graph_app_roles
      state_role   = "Storage Blob Data Reader"
      subjects = {
        pull-request = "${var.ca_github_oidc_subject_prefix}:pull_request"
        main-branch  = "${var.ca_github_oidc_subject_prefix}:ref:refs/heads/main"
      }
    }
    apply = {
      display_name = "ca-apply"
      description  = "Read/write: terraform apply from the approval-gated production environment"
      graph_roles  = var.ca_apply_graph_app_roles
      state_role   = "Storage Blob Data Contributor"
      subjects = {
        production = "${var.ca_github_oidc_subject_prefix}:environment:production"
      }
    }
  }

  # Flattened {identity, subject-name} pairs for the federated credentials.
  ca_federated_credentials = merge([
    for id, cfg in local.ca_identities : {
      for name, subject in cfg.subjects : "${id}/${name}" => {
        identity = id
        name     = name
        subject  = subject
      }
    }
  ]...)

  # Flattened {identity, permission} pairs for admin consent.
  ca_graph_grants = merge([
    for id, cfg in local.ca_identities : {
      for role in cfg.graph_roles : "${id}/${role}" => {
        identity = id
        role     = role
      }
    }
  ]...)
}

resource "azuread_application" "ca" {
  for_each = local.ca_identities

  display_name     = each.value.display_name
  description      = each.value.description
  sign_in_audience = "AzureADMyOrg"
  owners           = [local.admin_object_id]

  required_resource_access {
    resource_app_id = data.azuread_service_principal.msgraph.client_id

    dynamic "resource_access" {
      for_each = toset(each.value.graph_roles)

      content {
        id   = data.azuread_service_principal.msgraph.app_role_ids[resource_access.value]
        type = "Role"
      }
    }
  }
}

resource "azuread_service_principal" "ca" {
  for_each = local.ca_identities

  client_id = azuread_application.ca[each.key].client_id
  owners    = [local.admin_object_id]
}

# One federated credential per trusted GitHub context. The `subject` must
# match the token's `sub` claim exactly. Note that a job which declares an
# `environment:` gets the environment subject, not the branch one, so
# ca-apply is unreachable from any job that skips the approval gate.
resource "azuread_application_federated_identity_credential" "ca_github" {
  for_each = local.ca_federated_credentials

  application_id = azuread_application.ca[each.value.identity].id
  display_name   = "github-${each.value.name}"
  description    = "GitHub Actions, ${var.ca_github_repository} (${each.value.name})"
  issuer         = "https://token.actions.githubusercontent.com"
  audiences      = ["api://AzureADTokenExchange"]
  subject        = each.value.subject
}

# Admin consent, one assignment per permission.
resource "azuread_app_role_assignment" "ca_graph" {
  for_each = local.ca_graph_grants

  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids[each.value.role]
  principal_object_id = azuread_service_principal.ca[each.value.identity].object_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}

# State access on the shared tfstate container, which also holds this repo's
# state. ca-plan reads the blob (it plans with -lock=false, so it never needs
# a lease); ca-apply reads, writes and leases it. Scoped to the container,
# not the account: account keys are disabled, so there is nothing at account
# level that unlocks the data.
resource "azurerm_role_assignment" "ca_state" {
  for_each = local.ca_identities

  scope                = "${data.azurerm_storage_account.tfstate.id}/blobServices/default/containers/tfstate"
  role_definition_name = each.value.state_role
  principal_id         = azuread_service_principal.ca[each.key].object_id
}
