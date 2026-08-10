#!/usr/bin/env bash
set -euo pipefail

pod_cidr="${POD_CIDR:-10.244.0.0/16}"
zone="${FIREWALL_ZONE:-canal-pods}"

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

# Bind only the pod CIDR to a dedicated zone and enable forwarding within that
# zone. The zone exposes no services and retains firewalld's default INPUT reject,
# so this does not trust pods to reach node-local services. Pod-to-public traffic
# also remains inter-zone and denied unless it has an explicit, separate policy.
if ! firewall-cmd --permanent --get-zones | tr ' ' '\n' | grep -Fxq "$zone"; then
  firewall-cmd --permanent --new-zone="$zone"
fi

firewall-cmd --permanent --zone="$zone" --add-source="$pod_cidr"
firewall-cmd --permanent --zone="$zone" --add-forward
firewall-cmd --check-config
firewall-cmd --reload

firewall-cmd --zone="$zone" --query-source="$pod_cidr"
firewall-cmd --zone="$zone" --query-forward

echo "firewalld permits intra-zone Canal pod forwarding for ${pod_cidr}."
