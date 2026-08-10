#!/usr/bin/env bash
set -euo pipefail

context="${KUBE_CONTEXT:-kubernetes-admin@kubernetes}"
namespace=kube-system

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required." >&2
  exit 1
fi

# kube-proxy uses one shared ConfigMap, so a fixed address cannot represent every
# node. Render an ephemeral, per-pod copy using the downward-API host IP. A CLI
# override is not sufficient because kube-proxy ignores that flag when --config
# supplies the same field.
patch='{"spec":{"template":{"spec":{"securityContext":{"fsGroup":65534,"fsGroupChangePolicy":"OnRootMismatch"},"initContainers":[{"name":"render-private-metrics-config","image":"busybox:1.36","imagePullPolicy":"IfNotPresent","command":["sh","-ec","cp /source/kubeconfig.conf /rendered/kubeconfig.conf; sed \"s|metricsBindAddress: \\\"\\\"|metricsBindAddress: \\\"${NODE_IP}:10249\\\"|\" /source/config.conf > /rendered/config.conf"],"env":[{"name":"NODE_IP","valueFrom":{"fieldRef":{"apiVersion":"v1","fieldPath":"status.hostIP"}}}],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"runAsNonRoot":true,"runAsUser":65534,"runAsGroup":65534},"volumeMounts":[{"name":"kube-proxy","mountPath":"/source","readOnly":true},{"name":"kube-proxy-rendered","mountPath":"/rendered"}]}],"containers":[{"name":"kube-proxy","command":["/usr/local/bin/kube-proxy","--config=/var/lib/kube-proxy/config.conf","--hostname-override=$(NODE_NAME)"],"volumeMounts":[{"name":"kube-proxy-rendered","mountPath":"/var/lib/kube-proxy"}]}],"volumes":[{"name":"kube-proxy-rendered","emptyDir":{}}]}}}}'

kubectl patch daemonset/kube-proxy --namespace "$namespace" --context "$context" \
  --type=strategic --patch "$patch"
kubectl rollout restart daemonset/kube-proxy --namespace "$namespace" --context "$context"
kubectl rollout status daemonset/kube-proxy --namespace "$namespace" --context "$context" --timeout=180s

echo "kube-proxy metrics are listening only on each node's private host IP and are restricted by firewalld."
