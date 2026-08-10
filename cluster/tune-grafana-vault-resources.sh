#!/usr/bin/env bash
set -euo pipefail

context="${KUBE_CONTEXT:-kubernetes-admin@kubernetes}"

kubectl --context="$context" patch deployment -n monitoring kps-grafana \
  --type=merge \
  -p '{"spec":{"template":{"metadata":{"annotations":{"vault.hashicorp.com/agent-requests-cpu":"0","vault.hashicorp.com/agent-limits-cpu":"100m"}}}}}'

kubectl --context="$context" rollout status deployment/kps-grafana \
  -n monitoring --timeout=10m
