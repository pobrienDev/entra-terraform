# Key Vault holding the app registration's client secret, so the automation
# tools fetch it at runtime instead of keeping it in a .env file.
#
# Honest caveat: Terraform generates the secret, so its value is also recorded
# in Terraform state. Key Vault keeps it out of code and config; keeping it
# safe in state is the job of the locked-down remote backend (see backend.tf).

data "azurerm_client_config" "current" {}

# Vault names are global DNS names (<name>.vault.azure.net), 3-24 chars.
resource "random_string" "kv_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_key_vault" "main" {
  name                = "kv-${var.name_prefix}-${random_string.kv_suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tenant_id           = var.tenant_id
  sku_name            = "standard"
  tags                = local.tags

  # Azure RBAC instead of legacy access policies: access is granted with
  # ordinary role assignments, auditable alongside everything else.
  rbac_authorization_enabled = true

  # Minimum retention and no purge protection so `terraform destroy` leaves
  # nothing behind in a learning tenant. Production would flip both.
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
}

# With RBAC mode, creating the vault grants no data access — not even to its
# creator. Whoever runs Terraform needs this to write the secret.
resource "azurerm_role_assignment" "deployer_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = local.admin_object_id
}

# Role assignments take a while to propagate; writing the secret immediately
# after fails with 403 on a first apply.
resource "time_sleep" "rbac_propagation" {
  create_duration = "60s"
  depends_on      = [azurerm_role_assignment.deployer_secrets_officer]
}

# Drives rotation: when the window elapses, the next apply replaces the
# password, and the Key Vault secret is updated to match.
resource "time_rotating" "client_secret" {
  rotation_days = var.client_secret_rotation_days
}

resource "azuread_application_password" "automation" {
  application_id = azuread_application.automation.id
  display_name   = "terraform-managed"
  end_date       = time_rotating.client_secret.rotation_rfc3339

  rotate_when_changed = {
    rotation = time_rotating.client_secret.id
  }
}

resource "azurerm_key_vault_secret" "client_secret" {
  name            = "graph-automation-client-secret"
  key_vault_id    = azurerm_key_vault.main.id
  value           = azuread_application_password.automation.value
  content_type    = "Entra app client secret"
  expiration_date = time_rotating.client_secret.rotation_rfc3339
  tags            = local.tags

  depends_on = [time_sleep.rbac_propagation]
}
