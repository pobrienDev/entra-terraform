# No defaults on the ID variables, on purpose: values live in the gitignored
# terraform.tfvars, so nothing tenant-specific is ever committed.

variable "tenant_id" {
  description = "Entra ID tenant to provision into."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$", lower(var.tenant_id)))
    error_message = "tenant_id must be a GUID."
  }
}

variable "subscription_id" {
  description = "Azure subscription to provision into."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$", lower(var.subscription_id)))
    error_message = "subscription_id must be a GUID."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "westus2"
}

variable "name_prefix" {
  description = "Short prefix applied to resource names."
  type        = string
  default     = "entra-iac"
}
