#!/usr/bin/env bash
set -euo pipefail

context="${KUBE_CONTEXT:-kubernetes-admin@kubernetes}"

gateway_arg="--providers.kubernetesgateway.nativelbbydefault=true"
ingress_arg="--providers.kubernetesingress.nativelbbydefault=true"

current_args="$(kubectl --context="$context" get daemonset traefik -n traefik \
  -o jsonpath='{.spec.template.spec.containers[0].args}')"

patch='[]'
if [[ "$current_args" != *"$gateway_arg"* ]]; then
  patch="${patch%]}{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"$gateway_arg\"}]"
fi
if [[ "$current_args" != *"$ingress_arg"* ]]; then
  if [[ "$patch" == '[]' ]]; then
    patch="[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"$ingress_arg\"}]"
  else
    patch="${patch%]},${patch#\[}"
  fi
fi

if [[ "$patch" != '[]' ]]; then
  kubectl --context="$context" patch daemonset traefik -n traefik \
    --type=json -p="$patch"
fi

kubectl --context="$context" rollout status daemonset/traefik \
  -n traefik --timeout=10m
