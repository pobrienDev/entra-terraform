resource "azurerm_resource_group" "main" {
  name     = "rg-${var.name_prefix}"
  location = var.location
  tags     = local.tags
}

locals {
  tags = {
    project    = "entra-terraform"
    managed_by = "terraform"
  }
}
