#!/usr/bin/env bash
# Tests for redact.sh: one case per identifier class, one for the noise filter,
# one proving ordinary plan lines pass through untouched. Exit code is the
# number of failures. Placeholders only: the pre-commit hook blocks real IDs,
# and the tenant domain is assembled so the hook does not reject this file.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
redact="$here/redact.sh"
fail=0

check() {
  local name="$1" input="$2" expected="$3" actual
  actual="$(printf '%s\n' "$input" | "$redact")"
  if [ "$actual" == "$expected" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name"; echo "  expected: $expected"; echo "  actual:   $actual"; fail=$((fail + 1))
  fi
}

guid="00000000-0000-0000-0000-000000000000"
domain="contoso.onmicrosoft"".com"

check "guid" \
  "tenant_id = \"$guid\"" \
  'tenant_id = "<guid>"'

check "tenant domain" \
  "user_principal_name = \"admin@$domain\"" \
  'user_principal_name = "admin@<tenant-domain>"'

check "key vault name" \
  'name = "kv-entra-iac-abc123"' \
  'name = "<key-vault>"'

check "state storage name" \
  'storage_account_name = "sttfstateabc12345"' \
  'storage_account_name = "<state-storage>"'

check "app role assignment id" \
  "- id = \"/servicePrincipals/$guid/appRoleAssignedTo/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\" -> null" \
  '- id = "/servicePrincipals/<guid>/appRoleAssignedTo/<assignment-id>" -> null'

check "url" \
  'id = "https://kv-entra-iac-abc123.vault.azure.net/secrets/x/0123456789abcdef"' \
  'id = "<url>"'

check "refresh noise dropped, plan lines kept" \
  "$(printf '%s\n' \
      "azuread_application.automation: Refreshing state... [id=/applications/$guid]" \
      'data.azuread_client_config.current: Reading...' \
      'Acquiring state lock. This may take a few moments...' \
      'Plan: 2 to add, 1 to change, 1 to destroy.')" \
  'Plan: 2 to add, 1 to change, 1 to destroy.'

check "ordinary lines pass through" \
  '  # azuread_app_role_assignment.graph["User.RevokeSessions.All"] will be created' \
  '  # azuread_app_role_assignment.graph["User.RevokeSessions.All"] will be created'

check "empty input" "" ""

echo "$fail failure(s)"
exit "$fail"
