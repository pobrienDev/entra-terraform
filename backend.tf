# Remote state in Azure Storage. Deliberately empty ("partial configuration"):
# the storage account name is supplied at init time from the gitignored
# backend.tfbackend, so it never lands in a public repo.
#
#   terraform init -backend-config=backend.tfbackend
#
# The storage account itself is created by ./bootstrap — see
# docs/remote-state-bootstrap.md.

terraform {
  backend "azurerm" {}
}
