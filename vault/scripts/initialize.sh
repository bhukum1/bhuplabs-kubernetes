#!/usr/bin/env bash
set -euo pipefail

context="${KUBERNETES_CONTEXT:-kubernetes-admin@kubernetes}"
namespace="${VAULT_NAMESPACE:-vault}"
pod="${VAULT_POD:-vault-0}"
keychain_account="${VAULT_KEYCHAIN_ACCOUNT:-${USER}}"
keychain_service="${VAULT_KEYCHAIN_SERVICE:-bhuplabs-vault-bootstrap}"

status_json="$(
  kubectl exec --context="$context" -n "$namespace" "$pod" \
    -- vault status -format=json 2>/dev/null || true
)"
initialized="$(printf '%s' "$status_json" | jq -r '.initialized')"

if [[ "$initialized" == "true" ]]; then
  echo "Vault is already initialized; refusing to generate new recovery material."
  exit 0
fi

bootstrap_json="$(
  kubectl exec --context="$context" -n "$namespace" "$pod" \
    -- vault operator init \
      -format=json \
      -key-shares=5 \
      -key-threshold=3
)"
bootstrap_hex="$(printf '%s' "$bootstrap_json" | xxd -p | tr -d '\n')"

security add-generic-password \
  -U \
  -a "$keychain_account" \
  -s "$keychain_service" \
  -w "$bootstrap_hex" >/dev/null

for key_index in 0 1 2; do
  unseal_key="$(
    printf '%s' "$bootstrap_json" |
      jq -r --argjson key_index "$key_index" '.unseal_keys_b64[$key_index]'
  )"
  printf '%s\n' "$unseal_key" |
    kubectl exec \
      --context="$context" \
      -n "$namespace" \
      -i "$pod" \
      -- vault operator unseal - >/dev/null
done

unset status_json bootstrap_json bootstrap_hex unseal_key
echo "Vault initialized and unsealed. Recovery material is stored in macOS Keychain."
kubectl exec --context="$context" -n "$namespace" "$pod" -- vault status
