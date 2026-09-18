# Rendered contents of the main config's backend file. Write it with:
#   terraform output -raw backend_config > ../backend.tfbackend
output "backend_config" {
  value = <<-EOT
    storage_account_name = "${azurerm_storage_account.tfstate.name}"
    container_name       = "${azurerm_storage_container.tfstate.name}"
    key                  = "entra-terraform.tfstate"
    use_azuread_auth     = true
  EOT
}
