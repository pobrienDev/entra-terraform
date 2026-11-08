#!/usr/bin/env bash
# Strips tenant identifiers from Terraform output before it reaches a public
# log, step summary or pull request comment. Reads stdin, writes stdout.
#
# This repository is public, so its logs are too. Raw plan output holds the
# tenant, subscription and object IDs, the Key Vault and state storage names,
# and app role assignment IDs (the principal's object ID plus a GUID,
# base64url-encoded, so the GUID pattern alone never catches them). GitHub's
# secret masking is the second layer; this is the first.
#
# The URL rule runs first: the Key Vault and storage rules insert angle
# brackets into a hostname, after which the URL rule would no longer match
# the whole address.
#
# Tested by redact_test.sh, which CI runs before every plan.
{ grep -vE 'Refreshing state|Reading\.\.\.|Read complete|Still reading|Acquiring state lock|Releasing state lock' || true; } \
  | sed -E \
      -e 's#https://[A-Za-z0-9./_-]+#<url>#g' \
      -e 's/[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}/<guid>/g' \
      -e 's/[A-Za-z0-9-]+\.onmicrosoft\.com/<tenant-domain>/g' \
      -e 's/kv-[a-z0-9-]+/<key-vault>/g' \
      -e 's/sttfstate[a-z0-9]+/<state-storage>/g' \
      -e 's#appRoleAssignedTo/[A-Za-z0-9_-]+#appRoleAssignedTo/<assignment-id>#g'
