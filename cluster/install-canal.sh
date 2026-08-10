#!/usr/bin/env bash
set -euo pipefail

context="${KUBE_CONTEXT:-kubernetes-admin@kubernetes}"
version=v3.32.1
expected_sha=aa58a7b245586a90d75d969b9184326f6218acea7e4951ce2931113cd8e91e39
manifest="$(mktemp)"
staged="$(mktemp)"
trap 'rm -f "$manifest" "$staged"' EXIT

curl -fsSLo "$manifest" "https://raw.githubusercontent.com/projectcalico/calico/${version}/manifests/canal.yaml"
actual_sha="$(shasum -a 256 "$manifest" | awk '{print $1}')"
if [[ "$actual_sha" != "$expected_sha" ]]; then
  echo "Canal manifest checksum mismatch" >&2
  exit 1
fi

python3 - "$manifest" "$staged" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()
source = source.replace('canal_iface: ""', 'canal_iface: "wg0"', 1)
source = source.replace(
    '"Network": "10.244.0.0/16",\n      "Backend"',
    '"Network": "10.244.0.0/16",\n      "EnableNFTables": false,\n      "Backend"',
    1,
)
source = source.replace(
    "image: docker.io/flannel/flannel:v0.24.4",
    "image: ghcr.io/flannel-io/flannel:v0.28.8",
    1,
)
source = source.replace(
    "nodeSelector:\n        kubernetes.io/os: linux\n      hostNetwork: true",
    "nodeSelector:\n        canal-migration: disabled\n      hostNetwork: true",
    1,
)
pathlib.Path(sys.argv[2]).write_text(source)
PY

kubectl apply --context="$context" --server-side --force-conflicts -f "$staged"
kubectl patch daemonset kube-flannel-ds -n kube-flannel --context="$context" --type=merge \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"canal-migration":"disabled"}}}}}'
kubectl wait --context="$context" -n kube-flannel --for=delete pod -l app=flannel --timeout=180s

if ! kubectl patch daemonset canal -n kube-system --context="$context" --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/nodeSelector","value":{"kubernetes.io/os":"linux"}}]' || \
  ! kubectl rollout status daemonset/canal -n kube-system --context="$context" --timeout=300s; then
  echo "Canal failed; restoring the original Flannel daemonset" >&2
  kubectl patch daemonset canal -n kube-system --context="$context" --type=merge \
    -p '{"spec":{"template":{"spec":{"nodeSelector":{"canal-migration":"disabled"}}}}}' || true
  kubectl patch daemonset kube-flannel-ds -n kube-flannel --context="$context" --type=json \
    -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]' || true
  kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --context="$context" --timeout=300s || true
  exit 1
fi

echo "Canal is ready on every node. Original Flannel is retained in disabled state for rollback."
