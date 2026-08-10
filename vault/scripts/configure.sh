#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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

vault_exec() {
  kubectl exec \
    --context="$context" \
    -n "$namespace" \
    "$pod" \
    -- env VAULT_TOKEN="$root_token" vault "$@"
}

vault_exec auth list -format=json |
  jq -e 'has("kubernetes/")' >/dev/null ||
  vault_exec auth enable kubernetes

vault_exec secrets list -format=json |
  jq -e 'has("secret/")' >/dev/null ||
  vault_exec secrets enable -path=secret kv-v2

vault_exec write auth/kubernetes/config \
  kubernetes_host=https://kubernetes.default.svc:443

kubectl exec \
  --context="$context" \
  -n "$namespace" \
  -i "$pod" \
  -- env VAULT_TOKEN="$root_token" vault policy write n8n - \
  < "$repo_root/vault/policies/n8n.hcl"

kubectl exec \
  --context="$context" \
  -n "$namespace" \
  -i "$pod" \
  -- env VAULT_TOKEN="$root_token" vault policy write postgres - \
  < "$repo_root/vault/policies/postgres.hcl"

vault_exec write auth/kubernetes/role/n8n \
  bound_service_account_names=n8n-vault \
  bound_service_account_namespaces=n8n \
  policies=n8n \
  ttl=1h

vault_exec write auth/kubernetes/role/postgres \
  bound_service_account_names=postgres-vault \
  bound_service_account_namespaces=n8n \
  policies=postgres \
  ttl=1h

vault_exec audit list -format=json |
  jq -e 'has("file/")' >/dev/null ||
  vault_exec audit enable file file_path=/vault/data/audit.log

unset bootstrap_hex root_token
echo "Vault Kubernetes authentication, policies, roles, and audit logging configured."
