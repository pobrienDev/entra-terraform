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

variable "graph_app_roles" {
  description = "Microsoft Graph application permissions the automation needs for its core job."
  type        = list(string)
  default = [
    "User.ReadWrite.All",    # create / update / disable accounts
    "Group.ReadWrite.All",   # group membership
    "AuditLog.Read.All",     # signInActivity, for stale-account detection
    "Organization.Read.All", # subscribedSkus, for license seat counts
  ]
}

variable "enable_credential_reset" {
  description = "Also grant the permissions that let the app reset passwords and remove MFA methods. Off by default: a leaked secret with these can take over any account."
  type        = bool
  default     = false
}

variable "credential_reset_app_roles" {
  description = "Granted only when enable_credential_reset is true."
  type        = list(string)
  default = [
    "User-PasswordProfile.ReadWrite.All",
    "UserAuthenticationMethod.ReadWrite.All",
  ]
}

variable "client_secret_rotation_days" {
  description = "Lifetime of the app's client secret. After this, the next apply rotates it."
  type        = number
  default     = 180
}

variable "github_repository" {
  description = "owner/name of the GitHub repository allowed to run plan via OIDC."
  type        = string
  default     = "pobrienDev/entra-terraform"
}

variable "github_oidc_subject_prefix" {
  description = "Prefix of the OIDC `sub` claim GitHub issues for this repo. Read it with: gh api repos/OWNER/REPO/actions/oidc/customization/sub --jq .sub_claim_prefix"
  type        = string
  default     = "repo:pobrienDev@24906399/entra-terraform@1376480422"
}

variable "state_storage_account_name" {
  description = "Storage account created by ./bootstrap. Not committed — set in terraform.tfvars."
  type        = string
}

variable "state_resource_group_name" {
  description = "Resource group created by ./bootstrap."
  type        = string
  default     = "rg-entra-iac-tfstate"
}

variable "admin_object_id" {
  description = "Object ID of the admin user who owns the app registrations and gets Key Vault secret access. Null means the identity running Terraform; CI must set it."
  type        = string
  default     = null
}
