# Identities that GitHub Actions workflows authenticate as: this repo's plan
# job, plus the jobs of two sibling repos. None has a client secret. GitHub
# mints a short-lived OIDC token per run and Entra ID trusts it through the
# federated credentials below, so there is nothing to store, rotate or leak.
#
# Subjects use GitHub's immutable format, repo:owner@id/name@id:<context>. A
# repo *name* can be re-registered by someone else after a rename or deletion
# and would inherit this trust; the numeric IDs can't be. Read a repo's prefix
# with:  gh api repos/OWNER/REPO/actions/oidc/customization/sub --jq .sub_claim_prefix
#
# The subject must match the token's `sub` claim exactly, or sign-in fails
# with AADSTS700213. A job that declares an `environment:` gets the
# environment subject rather than the branch one, so an identity trusted only
# from an approval-gated environment is unreachable from any job that skips it.

locals {
  github_owner         = "pobrienDev@24906399"
  tfstate_container_id = "${data.azurerm_storage_account.tfstate.id}/blobServices/default/containers/tfstate"

  github_identities = {
    # Plans this repo on every pull request. Every role is read-only, so it
    # can plan but never apply.
    ci = {
      display_name = "${var.name_prefix}-github-plan"
      description  = "Read-only: terraform plan for entra-terraform"
      repo         = "entra-terraform@1376480422"
      subjects     = { pull-request = "pull_request", main-branch = "ref:refs/heads/main" }
      graph_roles  = ["Application.Read.All"] # apps, service principals, consent grants
      azure_roles = {
        # One grant per thing `plan` has to refresh.
        rg-reader = { role = "Reader", scope = azurerm_resource_group.main.id }
        # Refreshing the Key Vault secret reads it. CI can already read state,
        # which holds the same value; the control is who can obtain a token.
        secrets-user = { role = "Key Vault Secrets User", scope = azurerm_key_vault.main.id }
        # Reader, not Contributor: it plans with -lock=false, so never needs a lease.
        state-read = { role = "Storage Blob Data Reader", scope = local.tfstate_container_id }
        # Management-plane read so the storage account data source resolves.
        state-account = { role = "Reader", scope = data.azurerm_storage_account.tfstate.id }
      }
    }

    # entra-credential-monitor: a daily scan for expiring app secrets and
    # certificates. Built in the portal first and imported, so its client ID
    # never changed. The monitor's own identity is one that can't expire.
    credmon = {
      display_name = "credmon-reader"
      description  = "Read-only: daily credential scan for entra-credential-monitor"
      repo         = "entra-credential-monitor@1387972681"
      subjects     = { actions-monitor = "environment:monitor" }
      graph_roles  = ["Application.Read.All", "User.ReadBasic.All"] # credential metadata; owner display names
      azure_roles  = {}
    }

    # entra-conditional-access manages the tenant's Conditional Access policies
    # as code. App-only identities are not subject to CA, so one that can write
    # policies could rewrite every policy in the tenant. Hence two identities:
    # the write permission is reachable only from that repo's approval-gated
    # `production` environment.
    ca-plan = {
      display_name = "ca-plan"
      description  = "Read-only: terraform plan on pull requests and daily drift detection"
      repo         = "entra-conditional-access@1391370842"
      subjects     = { pull-request = "pull_request", main-branch = "ref:refs/heads/main" }
      graph_roles  = ["Policy.Read.All", "Group.Read.All"] # policies and named locations; break-glass group
      azure_roles  = { state-read = { role = "Storage Blob Data Reader", scope = local.tfstate_container_id } }
    }
    ca-apply = {
      display_name = "ca-apply"
      description  = "Read/write: terraform apply from the approval-gated production environment"
      repo         = "entra-conditional-access@1391370842"
      subjects     = { production = "environment:production" }
      graph_roles  = ["Policy.Read.All", "Policy.ReadWrite.ConditionalAccess", "Group.Read.All"]
      azure_roles  = { state-write = { role = "Storage Blob Data Contributor", scope = local.tfstate_container_id } }
    }
  }

  # The table above, flattened to one entry per credential, grant and role.
  github_subjects = merge([for id, i in local.github_identities : {
    for name, ctx in i.subjects : "${id}/${name}" => {
      identity = id
      name     = name
      subject  = "repo:${local.github_owner}/${i.repo}:${ctx}"
      repo     = split("@", i.repo)[0]
    }
  }]...)
  github_graph_roles = merge([for id, i in local.github_identities : {
    for role in i.graph_roles : "${id}/${role}" => { identity = id, role = role }
  }]...)
  github_azure_roles = merge([for id, i in local.github_identities : {
    for name, r in i.azure_roles : "${id}/${name}" => merge(r, { identity = id })
  }]...)
}

resource "azuread_application" "github" {
  for_each = local.github_identities

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

resource "azuread_service_principal" "github" {
  for_each = local.github_identities

  client_id = azuread_application.github[each.key].client_id
  owners    = [local.admin_object_id]
}

# One credential per trusted GitHub context.
resource "azuread_application_federated_identity_credential" "github" {
  for_each = local.github_subjects

  application_id = azuread_application.github[each.value.identity].id
  display_name   = "github-${each.value.name}"
  description    = "GitHub Actions, pobrienDev/${each.value.repo} (${each.value.name})"
  issuer         = "https://token.actions.githubusercontent.com"
  audiences      = ["api://AzureADTokenExchange"]
  subject        = each.value.subject
}

# Admin consent, one assignment per permission.
resource "azuread_app_role_assignment" "github_graph" {
  for_each = local.github_graph_roles

  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids[each.value.role]
  principal_object_id = azuread_service_principal.github[each.value.identity].object_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}

# The state storage account created by ./bootstrap. The tfstate container is
# shared with entra-conditional-access, so its identities get blob access here.
# Scoped to the container: account keys are disabled, so nothing at account
# level unlocks the data.
data "azurerm_storage_account" "tfstate" {
  name                = var.state_storage_account_name
  resource_group_name = "rg-${var.name_prefix}-tfstate"
}

resource "azurerm_role_assignment" "github" {
  for_each = local.github_azure_roles

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azuread_service_principal.github[each.value.identity].object_id
}
