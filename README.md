# entra-terraform

[![terraform plan](https://github.com/pobrienDev/entra-terraform/actions/workflows/plan.yml/badge.svg)](https://github.com/pobrienDev/entra-terraform/actions/workflows/plan.yml)

The Microsoft Entra ID and Azure infrastructure my Graph API automation tools
depend on, as versioned, reviewable Terraform instead of portal clicks.

My two Python CLIs, [employee-provisioning-tool](https://github.com/pobrienDev/employee-provisioning-tool)
and [entra-stale-accounts](https://github.com/pobrienDev/entra-stale-accounts),
both start with the same manual setup: register an app, add Graph permissions,
grant admin consent, create a secret, paste it into a `.env`. This repository
replaces that setup. The two layers stay separate and share no code:

| Layer | Tool | Responsibility |
|---|---|---|
| Infrastructure | Terraform (this repo) | Creates the app registration, permissions, service principal and secret storage the automation authenticates as |
| Application | the Python CLIs | Use that identity to manage accounts day to day |

Everything here runs against a personal tenant and an Azure free-tier
subscription.

## What it provisions

Scope is fixed at five things, deliberately:

1. **Resource group** — `main.tf`
2. **App registration** for Graph automation, with least-privilege application permissions — `entra.tf`
3. **Service principal + app role assignments** — the code equivalent of clicking "Grant admin consent" — `entra.tf`
4. **Key Vault** (RBAC mode) holding the app's client secret, which rotates every 180 days — `keyvault.tf`
5. **Remote state** in a locked-down Azure Storage account, created by a separate bootstrap config — `bootstrap/`, `backend.tf`

Plus the CI identity that plans all of the above on every pull request, with
no stored credentials — `ci.tf`, `.github/workflows/plan.yml`.

```
.
├── main.tf, entra.tf, keyvault.tf   the five resources
├── ci.tf                            read-only identity for GitHub Actions (OIDC)
├── backend.tf                       remote state (partial config, no names committed)
├── bootstrap/                       one-time config that creates the state storage
├── docs/                            bootstrap explanation, drift-detection output
├── .github/workflows/plan.yml       terraform plan on every PR
└── .githooks/pre-commit             blocks IDs, secrets and state from being committed
```

## Design decisions

**Permissions come from the code that uses them.** The Graph permissions aren't
a guess: I read both tools' Graph calls and granted what they need —
`User.ReadWrite.All`, `Group.ReadWrite.All`, `AuditLog.Read.All`,
`Organization.Read.All`. The two permissions that let an app reset passwords
and remove MFA methods are behind `enable_credential_reset`, **off by
default**. A leaked secret with those can take over any account in the tenant,
so they should be a decision, not a default.

**Declaring a permission is not granting it.** `required_resource_access` only
lists what the app *requests*. The grant is a separate
`azuread_app_role_assignment` per permission. Permission IDs are looked up by
name from Microsoft Graph's service principal, so the config reads
`"User.ReadWrite.All"` rather than an opaque GUID.

**Key Vault keeps the secret out of code — not out of state.** Terraform
generates the client secret, so the value is recorded in Terraform state in
plaintext. That's unavoidable with this approach, and worth saying plainly:
Key Vault solves "secret in a `.env` file"; the state backend has to solve the
rest. Which is why:

**State storage is locked down like the credential store it is.** Account keys
disabled (Entra ID auth only), no anonymous access, TLS 1.2+, a data-plane role
scoped to the one container, blob versioning and soft delete for recovery, and
its own resource group so `terraform destroy` can't delete the state it's
using.

**RBAC mode means even the creator has no access.** With
`rbac_authorization_enabled`, creating a vault grants nothing on its contents.
The config assigns the admin `Key Vault Secrets Officer`, then waits 60 seconds
before writing the secret — role assignments take time to propagate, and
without the wait a first apply fails with a 403.

**Nothing identifying is committed.** Tenant and subscription IDs live in a
gitignored `terraform.tfvars`; the state storage account name is passed at
`init` via a gitignored partial backend config. A dependency-free pre-commit
hook (`.githooks/pre-commit`) blocks state files, variable files, GUIDs,
secret-shaped strings and tenant domains, plus a private denylist that is
itself never tracked.

## Remote state and the bootstrap problem

Terraform loads its backend before it reads any resources, so a config can't
create the storage account that holds its own state. This repo solves that
with two root modules: `bootstrap/` creates the state storage and keeps its
own tiny, secret-free state locally; the root config stores its state in what
bootstrap created.

The full explanation — why remote state, why bootstrap's local state is a
deliberate trade-off, and the one-time migration steps — is in
[docs/remote-state-bootstrap.md](docs/remote-state-bootstrap.md).

## State vs. reality

After the first apply I deleted the resource group by hand in the portal and
ran `terraform plan` with no code changes
([full output](docs/drift-detection.txt)):

```
azurerm_resource_group.main: Refreshing state... [id=/subscriptions/<redacted>/resourceGroups/rg-entra-iac]

  # azurerm_resource_group.main will be created
  + resource "azurerm_resource_group" "main" {
      + location = "westus2"
      + name     = "rg-entra-iac"
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

Terraform has no memory of what it *did*. Every plan is a three-way
comparison: the code says what should exist, state says what Terraform believes
exists, and the refresh asks Azure what actually exists. The portal deletion
made state and reality disagree, the refresh caught it, and the plan proposed
closing the gap — touching only the one resource that drifted.

## CI: `terraform plan` on every PR, with no stored secret

The workflow authenticates with **OIDC workload identity federation**. GitHub
mints a short-lived token for each run; a federated credential on a dedicated
CI app registration tells Entra ID to trust tokens from this repository. There
is no client secret to store, rotate or leak.

The CI identity is read-only by construction: `Application.Read.All` on Graph,
`Reader` on the workload resource group and state storage account, and
`Storage Blob Data Reader` on the state container. It plans with `-lock=false`
so it never needs write access to take a lease. It can plan; it cannot apply.

Because this repository is public, so are its logs. Raw plan output contains
tenant, subscription and object IDs, so the workflow writes it to a file, and
only a redacted copy is ever printed or posted to the PR. GitHub's secret
masking is the second layer.

One honest limitation: refreshing `azurerm_key_vault_secret` reads the secret,
so the CI identity holds `Key Vault Secrets User`. It can already read state,
which contains the same value — anything able to plan this config can see that
secret. The control is who can get a token: workflows in this repo only, and
GitHub never issues one to pull requests from forks.

### Three things CI taught me

Getting to the first green run took three fixes.

**1. `AADSTS700213: No matching federated identity record`.** The credential's
subject was `repo:owner/name:ref:refs/heads/main`, but the token's `sub` claim
was `repo:owner@<id>/name@<id>:ref:refs/heads/main`. GitHub's newer immutable
subject format embeds numeric owner and repo IDs. The match must be exact, so
I changed the credential rather than turning the feature off: a repo *name*
can be re-registered by someone else after a rename or deletion and would
inherit the cloud trust, while an ID can't be.

**2. `403` reading the storage account.** I'd scoped CI's `Reader` role to the
state *container*, but a data source in the config reads the storage *account*.
The fix was moving one role assignment up one scope — still read-only, and
with account keys disabled there's nothing at that level that unlocks the data.

**3. CI's plan disagreed with mine.** Same code, same state — locally "No
changes", in CI "4 to change, 1 to replace". The config set each resource's
`owners` to *whoever is running Terraform*. Locally that's me; in CI it's the
CI identity, so CI's plan proposed making itself the owner of everything.
Infrastructure code shouldn't mean different things depending on who runs it.
The owner is now an explicit input (`admin_object_id`), and CI's plan matches
mine. I wouldn't have found this one without a second identity running the
same code — which is a good argument for CI on infrastructure repos by itself.

## Evidence it runs

First apply against a real tenant (IDs redacted):

```
azuread_application.automation: Creation complete after 3s [id=/applications/<redacted>]
azuread_service_principal.automation: Creation complete after 2s [id=/servicePrincipals/<redacted>]
azuread_app_role_assignment.graph["Group.ReadWrite.All"]: Creation complete after 1s
azuread_app_role_assignment.graph["User.ReadWrite.All"]: Creation complete after 1s
azuread_app_role_assignment.graph["Organization.Read.All"]: Creation complete after 1s
azuread_app_role_assignment.graph["AuditLog.Read.All"]: Creation complete after 1s
azurerm_resource_group.main: Creation complete after 25s [id=/subscriptions/<redacted>/resourceGroups/rg-entra-iac]

Apply complete! Resources: 7 added, 0 changed, 0 destroyed.

Outputs:

application_client_id = "<redacted>"
granted_graph_permissions = tolist([
  "AuditLog.Read.All",
  "Group.ReadWrite.All",
  "Organization.Read.All",
  "User.ReadWrite.All",
])
resource_group_name = "rg-entra-iac"
```

Key Vault apply, showing the propagation wait doing its job — the secret
writes in 2 seconds with no 403:

```
azurerm_role_assignment.deployer_secrets_officer: Creation complete after 27s
time_sleep.rbac_propagation: Creation complete after 1m0s
azurerm_key_vault_secret.client_secret: Creation complete after 2s

Apply complete! Resources: 7 added, 0 changed, 0 destroyed.
```

And CI's comment on [pull request #1](https://github.com/pobrienDev/entra-terraform/pull/1),
after the third fix above:

```
No changes. Your infrastructure matches the configuration.
```

## Running it yourself

Prerequisites: Terraform ≥ 1.9, Azure CLI, and a tenant where you can grant
admin consent.

1. Sign in, enable the leak guard, and create your variables file:

   ```bash
   az login --tenant <your-tenant-id>
   git config core.hooksPath .githooks
   cp terraform.tfvars.example terraform.tfvars   # fill in tenant + subscription IDs
   ```

2. One time only, create the state storage and write the backend file:

   ```bash
   cd bootstrap
   terraform init
   terraform apply -var-file=../terraform.tfvars
   terraform output -raw backend_config > ../backend.tfbackend
   cd ..
   ```

3. Copy the `storage_account_name` from `backend.tfbackend` into
   `terraform.tfvars` as `state_storage_account_name`.

4. Initialize against the remote backend and apply:

   ```bash
   terraform init -backend-config=backend.tfbackend
   terraform plan
   terraform apply
   ```

For CI, set the `github_oidc_subject_prefix` variable to your repo's value
(`gh api repos/OWNER/REPO/actions/oidc/customization/sub --jq .sub_claim_prefix`)
and add these Actions secrets: `AZURE_CLIENT_ID` (the `ci_client_id` output),
`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `TFSTATE_STORAGE_ACCOUNT`,
`ADMIN_OBJECT_ID`, and `TENANT_NAME` (masked from logs).

To tear down: `terraform destroy` in the root, then in `bootstrap/`.

## What I'd do differently in production

- Purge protection on, longer soft-delete retention, and private endpoints for
  Key Vault and the state storage account instead of public network access.
- A certificate or a managed identity instead of a client secret for the
  automation app, which would keep the credential out of state entirely.
- A separate apply pipeline with a protected environment and required
  reviewers, rather than applying from a laptop.
- Split state per environment once there's more than one.

Scope stayed at five resources on purpose. The goal was something finished and
explainable end to end, not something sprawling.
