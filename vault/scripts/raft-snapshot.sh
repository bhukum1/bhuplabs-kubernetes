#!/usr/bin/env bash
set -euo pipefail

context="${KUBERNETES_CONTEXT:-kubernetes-admin@kubernetes}"
namespace="${VAULT_NAMESPACE:-vault}"
pod="${VAULT_POD:-vault-0}"
keychain_account="${VAULT_KEYCHAIN_ACCOUNT:-${USER}}"
keychain_service="${VAULT_KEYCHAIN_SERVICE:-bhuplabs-vault-bootstrap}"
snapshot_path="${1:-vault-raft-$(date -u +%Y%m%dT%H%M%SZ).snap}"
pod_snapshot="/tmp/vault-raft.snap"

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

kubectl exec \
  --context="$context" \
  -n "$namespace" \
  "$pod" \
  -- env VAULT_TOKEN="$root_token" \
    vault operator raft snapshot save "$pod_snapshot"

kubectl cp \
  --context="$context" \
  "$namespace/$pod:$pod_snapshot" \
  "$snapshot_path"

kubectl exec \
  --context="$context" \
  -n "$namespace" \
  "$pod" \
  -- rm -f "$pod_snapshot"

chmod 600 "$snapshot_path"
unset bootstrap_hex root_token
echo "Encrypted Raft snapshot saved to $snapshot_path"
