# Remote state and the bootstrap problem

## Why remote state at all

Terraform's state file is its record of what it created. By default it's a
local file, which has three problems:

1. **It contains secrets.** This config generates an app registration client
   secret. Key Vault keeps that secret out of code and config, but Terraform
   still records the value in state, in plaintext. A state file on a laptop is
   a credential sitting on a laptop.
2. **It's a single copy.** Lose the file and Terraform forgets it owns
   anything; every resource has to be re-imported by hand.
3. **It can't be shared.** CI can't plan against a file that only exists on
   one machine, and two people applying at once would corrupt it.

An Azure Storage backend fixes all three: access is controlled by Entra ID
RBAC, blob versioning keeps every previous state, and the backend takes a
blob lease as a lock so concurrent applies are refused.

## The chicken-and-egg problem

Terraform loads its backend *before* it reads any resources. So this can't work:

```hcl
terraform {
  backend "azurerm" { storage_account_name = "..." }  # needs the account to exist
}

resource "azurerm_storage_account" "tfstate" { ... }  # ...but this creates it
```

`terraform init` would fail looking for a storage account that the same
config hasn't created yet. Something has to exist first.

## How this repo solves it

Two root modules, each with its own state:

| | `bootstrap/` | repo root |
|---|---|---|
| Creates | state resource group, storage account, container, RBAC role | everything else |
| Its own state lives | locally, in `bootstrap/terraform.tfstate` (gitignored) | in the storage account `bootstrap/` created |
| Run how often | once | every change |
| State contains secrets | no | yes |

`bootstrap/` keeping local state is a deliberate trade-off, not an oversight:
it holds four resources and no secrets, it almost never changes, and if its
state is lost the resources can be re-imported in four commands. Pushing the
problem down one more level would just need a bootstrap for the bootstrap.

The state storage sits in its **own resource group** so that
`terraform destroy` on the main config can't delete the state it's using.

## Hardening choices on the storage account

- `shared_access_key_enabled = false` — no account keys exist to leak.
  Access is Entra ID only, which is why the backend sets `use_azuread_auth`.
- `Storage Blob Data Contributor`, scoped to the one container — subscription
  Owner does not grant data-plane access, so this role is required even for
  the account's creator.
- No anonymous blob access, TLS 1.2 minimum, HTTPS only.
- Blob versioning plus 14-day soft delete — a bad apply or a deleted state
  blob is recoverable.
- The account name is not committed. `backend.tf` is a partial configuration;
  the name is passed at init from a gitignored `backend.tfbackend`.

## One-time setup

```bash
# 1. Create the state storage (local state, run once)
cd bootstrap
terraform init
terraform apply -var-file=../terraform.tfvars

# 2. Write the backend file for the main config
terraform output -raw backend_config > ../backend.tfbackend
cd ..

# 3. Point the main config at it. If local state already exists, Terraform
#    offers to copy it into the storage account — answer yes.
terraform init -backend-config=backend.tfbackend -migrate-state

# 4. Verify: no changes, and the state now comes from Azure
terraform plan

# 5. Remove the local copies — they still hold the client secret
rm terraform.tfstate terraform.tfstate.backup
```

Give the role assignment from step 1 a minute or two to propagate before
step 3; a `403 AuthorizationPermissionMismatch` at init means it hasn't yet.
