# Bootstrap: the storage account that holds the main configuration's state.
#
# This is a separate root module with its own (local) state, because the main
# config can't create the thing it needs in order to start. Run once; see
# docs/remote-state-bootstrap.md.

terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}

  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id

  # Account keys are disabled below, so the provider must use Entra ID auth
  # for storage data-plane calls too.
  storage_use_azuread = true
}

data "azurerm_client_config" "current" {}

# Separate resource group from the workload, so `terraform destroy` on the
# main config can never take its own state down with it.
resource "azurerm_resource_group" "tfstate" {
  name     = "rg-${var.name_prefix}-tfstate"
  location = var.location
  tags     = local.tags
}

# Storage account names are global DNS names: 3-24 chars, lowercase alphanumeric.
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_storage_account" "tfstate" {
  name                     = "sttfstate${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = local.tags

  # State contains the client secret in plaintext, so lock the account down:
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false # no anonymous blob access, ever
  shared_access_key_enabled       = false # no account keys; Entra ID + RBAC only

  blob_properties {
    versioning_enabled = true # every state write keeps the previous version

    delete_retention_policy {
      days = 14
    }
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# Being subscription Owner grants no access to blob *data*. Whoever runs
# Terraform needs this role to read and write state.
resource "azurerm_role_assignment" "state_writer" {
  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

locals {
  tags = {
    project    = "entra-terraform"
    managed_by = "terraform-bootstrap"
  }
}
