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
bootstrap_json="$(printf '%s' "$bootstrap_hex" | xxd -r -p)"

sealed="$(
  kubectl exec \
    --context="$context" \
    -n "$namespace" \
    "$pod" \
    -- vault status -format=json 2>/dev/null |
    jq -r '.sealed'
)" || true

if [[ "$sealed" == "false" ]]; then
  echo "Vault is already unsealed."
  unset bootstrap_hex bootstrap_json sealed
  kubectl exec \
    --context="$context" \
    -n "$namespace" \
    "$pod" \
    -- vault status
  exit 0
fi

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

unset bootstrap_hex bootstrap_json unseal_key sealed
kubectl exec \
  --context="$context" \
  -n "$namespace" \
  "$pod" \
  -- vault status
