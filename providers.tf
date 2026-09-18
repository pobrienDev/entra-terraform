# Both providers are pinned to an explicit tenant/subscription rather than
# inheriting whatever `az login` session happens to be active. If the CLI is
# logged into a different tenant, plan fails instead of targeting it.

provider "azurerm" {
  features {}

  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
}

provider "azuread" {
  tenant_id = var.tenant_id
}
