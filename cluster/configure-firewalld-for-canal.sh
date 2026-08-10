#!/usr/bin/env bash
set -euo pipefail

pod_cidr="${POD_CIDR:-10.244.0.0/16}"
zone="${FIREWALL_ZONE:-public}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script as root on every Kubernetes node." >&2
  exit 1
fi

if ! command -v firewall-cmd >/dev/null 2>&1; then
  echo "firewall-cmd is not installed; no changes were made." >&2
  exit 1
fi

if [[ "$(firewall-cmd --state)" != "running" ]]; then
  echo "firewalld is not running; no changes were made." >&2
  exit 1
fi

# Canal workload interfaces are named cali*, not cni0. They fall through to the
# public zone on these hosts. Allow only forwarded pod-to-pod traffic; do not put
# the pod CIDR or a wildcard cali interface in the trusted zone because that would
# also weaken the node-local INPUT boundary. Calico NetworkPolicy is evaluated
# before this later firewalld forwarding hook.
rule="rule family=\"ipv4\" source address=\"${pod_cidr}\" destination address=\"${pod_cidr}\" accept"
firewall-cmd --permanent --zone="$zone" --add-rich-rule="$rule"
firewall-cmd --zone="$zone" --add-rich-rule="$rule"

firewall-cmd --permanent --zone="$zone" --query-rich-rule="$rule"
firewall-cmd --zone="$zone" --query-rich-rule="$rule"

echo "firewalld permits Calico-approved pod-to-pod forwarding for ${pod_cidr}."
