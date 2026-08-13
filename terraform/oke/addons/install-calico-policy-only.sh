#!/usr/bin/env bash
set -euo pipefail

CALICO_VERSION="v3.32.0"
UPSTREAM_SHA256="0b09d96323cf250ad028450d2954fc0068ce4104545f1eab823f359a48eb69a3"
RENDERED_SHA256="f60e345a3e6303aeaed1fd5a791d9ebe84dd6369bfc441bc15c62e8255962c49"
UPSTREAM_URL="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico-policy-only.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(mktemp -d)"
UPSTREAM_FILE="${WORK_DIR}/calico-policy-only.upstream.yaml"
RENDERED_FILE="${WORK_DIR}/calico-policy-only.oci.yaml"

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

for command_name in curl patch sha256sum kubectl; do
  command -v "${command_name}" >/dev/null || {
    echo "Required command not found: ${command_name}" >&2
    exit 1
  }
done

curl --fail --silent --show-error --location "${UPSTREAM_URL}" --output "${UPSTREAM_FILE}"
echo "${UPSTREAM_SHA256}  ${UPSTREAM_FILE}" | sha256sum --check --status
patch --silent --output="${RENDERED_FILE}" "${UPSTREAM_FILE}" "${SCRIPT_DIR}/calico-oci-policy-only.patch"
echo "${RENDERED_SHA256}  ${RENDERED_FILE}" | sha256sum --check --status

kubectl apply --server-side --dry-run=server -f "${RENDERED_FILE}" >/dev/null

if [[ "${APPLY:-false}" != "true" ]]; then
  echo "Calico ${CALICO_VERSION} OCI policy-only manifest passed checksum and server validation."
  echo "Run with APPLY=true to install it."
  exit 0
fi

kubectl apply --server-side --field-manager=localshops-platform -f "${RENDERED_FILE}"
kubectl rollout status daemonset/calico-node -n kube-system --timeout=180s
kubectl rollout status deployment/calico-typha -n kube-system --timeout=180s
kubectl rollout status deployment/calico-kube-controllers -n kube-system --timeout=180s
kubectl get pods -n kube-system -l 'k8s-app in (calico-node,calico-typha,calico-kube-controllers)' -o wide
