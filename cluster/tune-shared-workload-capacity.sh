#!/usr/bin/env bash
set -euo pipefail

context="${KUBE_CONTEXT:-kubernetes-admin@kubernetes}"

# Vault-injected init containers participate in scheduling for the entire pod
# lifetime. Keep their requests proportional to these small workloads.
kubectl patch statefulset n8n-postgres -n n8n --context="$context" --type=merge -p \
  '{"spec":{"template":{"metadata":{"annotations":{"vault.hashicorp.com/agent-requests-cpu":"100m"}}}}}'

kubectl patch deployment n8n -n n8n --context="$context" --type=strategic -p \
  '{"spec":{"template":{"metadata":{"annotations":{"vault.hashicorp.com/agent-requests-cpu":"20m"}},"spec":{"containers":[{"name":"n8n","resources":{"requests":{"cpu":"100m"}}}]}}}}'

kubectl patch deployment n8n-oauth2-proxy -n n8n --context="$context" --type=merge -p \
  '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":0,"maxUnavailable":1}},"template":{"metadata":{"annotations":{"vault.hashicorp.com/agent-requests-cpu":"20m"}},"spec":{"nodeSelector":{"kubernetes.io/hostname":"node01"}}}}}'

# Two replicas retain webhook availability while a no-surge rollout avoids
# requiring temporary capacity that the small worker nodes do not have.
kubectl patch deployment vault-agent-injector -n vault --context="$context" --type=merge -p \
  '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":0,"maxUnavailable":1}}}}'

kubectl rollout status deployment/n8n -n n8n --context="$context" --timeout=240s
kubectl rollout status deployment/n8n-oauth2-proxy -n n8n --context="$context" --timeout=240s
kubectl rollout status deployment/vault-agent-injector -n vault --context="$context" --timeout=240s

kubectl describe node node01 --context="$context" | sed -n '/Allocated resources:/,/Events:/p'
