#!/usr/bin/env bash
set -euo pipefail

context="${KUBERNETES_CONTEXT:-kubernetes-admin@kubernetes}"
namespace="${VAULT_NAMESPACE:-vault}"
pod="${VAULT_POD:-vault-0}"
keychain_account="${VAULT_KEYCHAIN_ACCOUNT:-${USER}}"
keychain_service="${VAULT_KEYCHAIN_SERVICE:-bhuplabs-vault-bootstrap}"

bootstrap_hex="$(
  security find-generic-password \
    -a "$keychain_account" \
    -s "$keychain_service" \
    -w
)"
root_token="$(
  printf '%s' "$bootstrap_hex" |
    xxd -r -p |
    jq -jr '.root_token'
)"

read -r -s -p "n8n encryption key: " encryption_key
printf '\n'
read -r -s -p "n8n PostgreSQL password: " postgres_password
printf '\n'

printf '%s' "$encryption_key" |
  kubectl exec \
    --context="$context" \
    -n "$namespace" \
    -i "$pod" \
    -- env VAULT_TOKEN="$root_token" \
      vault kv put secret/n8n/application encryption_key=-

printf '%s' "$postgres_password" |
  kubectl exec \
    --context="$context" \
    -n "$namespace" \
    -i "$pod" \
    -- env VAULT_TOKEN="$root_token" \
      vault kv put secret/n8n/postgres password=-

unset bootstrap_hex root_token encryption_key postgres_password
echo "n8n values written to Vault; no Kubernetes Secret was created."
