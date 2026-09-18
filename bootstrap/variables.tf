# Same variables as the root config, so both can share one tfvars file:
#   terraform apply -var-file=../terraform.tfvars

variable "tenant_id" {
  type = string
}

variable "subscription_id" {
  type = string
}

variable "location" {
  type    = string
  default = "westus2"
}

variable "name_prefix" {
  type    = string
  default = "entra-iac"
}
