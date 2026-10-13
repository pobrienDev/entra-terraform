# The GitHub identities used to be three hand-written files (ci.tf, credmon.tf,
# ca.tf) and are now one table in github.tf. These record the renames so
# Terraform updates state addresses instead of destroying and recreating the
# apps — their client IDs are wired into three repos' secrets. Safe to delete
# once every state that used the old addresses has been applied.

moved {
  from = azuread_application.ci
  to   = azuread_application.github["ci"]
}
moved {
  from = azuread_application.credmon
  to   = azuread_application.github["credmon"]
}
moved {
  from = azuread_application.ca["plan"]
  to   = azuread_application.github["ca-plan"]
}
moved {
  from = azuread_application.ca["apply"]
  to   = azuread_application.github["ca-apply"]
}

moved {
  from = azuread_service_principal.ci
  to   = azuread_service_principal.github["ci"]
}
moved {
  from = azuread_service_principal.credmon
  to   = azuread_service_principal.github["credmon"]
}
moved {
  from = azuread_service_principal.ca["plan"]
  to   = azuread_service_principal.github["ca-plan"]
}
moved {
  from = azuread_service_principal.ca["apply"]
  to   = azuread_service_principal.github["ca-apply"]
}

moved {
  from = azuread_application_federated_identity_credential.github["pull-request"]
  to   = azuread_application_federated_identity_credential.github["ci/pull-request"]
}
moved {
  from = azuread_application_federated_identity_credential.github["main-branch"]
  to   = azuread_application_federated_identity_credential.github["ci/main-branch"]
}
moved {
  from = azuread_application_federated_identity_credential.credmon_github
  to   = azuread_application_federated_identity_credential.github["credmon/actions-monitor"]
}
moved {
  from = azuread_application_federated_identity_credential.ca_github["plan/pull-request"]
  to   = azuread_application_federated_identity_credential.github["ca-plan/pull-request"]
}
moved {
  from = azuread_application_federated_identity_credential.ca_github["plan/main-branch"]
  to   = azuread_application_federated_identity_credential.github["ca-plan/main-branch"]
}
moved {
  from = azuread_application_federated_identity_credential.ca_github["apply/production"]
  to   = azuread_application_federated_identity_credential.github["ca-apply/production"]
}

moved {
  from = azuread_app_role_assignment.ci_graph_read
  to   = azuread_app_role_assignment.github_graph["ci/Application.Read.All"]
}
moved {
  from = azuread_app_role_assignment.credmon_graph["Application.Read.All"]
  to   = azuread_app_role_assignment.github_graph["credmon/Application.Read.All"]
}
moved {
  from = azuread_app_role_assignment.credmon_graph["User.ReadBasic.All"]
  to   = azuread_app_role_assignment.github_graph["credmon/User.ReadBasic.All"]
}
moved {
  from = azuread_app_role_assignment.ca_graph["plan/Policy.Read.All"]
  to   = azuread_app_role_assignment.github_graph["ca-plan/Policy.Read.All"]
}
moved {
  from = azuread_app_role_assignment.ca_graph["plan/Group.Read.All"]
  to   = azuread_app_role_assignment.github_graph["ca-plan/Group.Read.All"]
}
moved {
  from = azuread_app_role_assignment.ca_graph["apply/Policy.Read.All"]
  to   = azuread_app_role_assignment.github_graph["ca-apply/Policy.Read.All"]
}
moved {
  from = azuread_app_role_assignment.ca_graph["apply/Policy.ReadWrite.ConditionalAccess"]
  to   = azuread_app_role_assignment.github_graph["ca-apply/Policy.ReadWrite.ConditionalAccess"]
}
moved {
  from = azuread_app_role_assignment.ca_graph["apply/Group.Read.All"]
  to   = azuread_app_role_assignment.github_graph["ca-apply/Group.Read.All"]
}

moved {
  from = azurerm_role_assignment.ci_reader
  to   = azurerm_role_assignment.github["ci/rg-reader"]
}
moved {
  from = azurerm_role_assignment.ci_kv_secrets_user
  to   = azurerm_role_assignment.github["ci/kv-secrets"]
}
moved {
  from = azurerm_role_assignment.ci_state_reader
  to   = azurerm_role_assignment.github["ci/state-read"]
}
moved {
  from = azurerm_role_assignment.ci_state_account_reader
  to   = azurerm_role_assignment.github["ci/state-account"]
}
moved {
  from = azurerm_role_assignment.ca_state["plan"]
  to   = azurerm_role_assignment.github["ca-plan/state-read"]
}
moved {
  from = azurerm_role_assignment.ca_state["apply"]
  to   = azurerm_role_assignment.github["ca-apply/state-write"]
}
