#!/usr/bin/env bash
set -euo pipefail

pod_cidr="${POD_CIDR:-10.244.0.0/16}"
zone="${FIREWALL_ZONE:-canal-pods}"
egress_policy="${EGRESS_POLICY:-canal-egress}"
host_monitoring_policy="${HOST_MONITORING_POLICY:-canal-hostmon}"
oci_dns_resolver="${OCI_DNS_RESOLVER:-169.254.169.254}"
monitoring_ports=(2381 6443 9100 10249 10250 10257 10259)
reload_required=false

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
# zone. The zone retains firewalld's default INPUT reject. The explicit ports
# below allow Prometheus to monitor node-local Kubernetes components; they do not
# expose those ports to public interfaces or other source zones.
if ! firewall-cmd --permanent --get-zones | tr ' ' '\n' | grep -Fxq "$zone"; then
  firewall-cmd --permanent --new-zone="$zone"
  reload_required=true
fi

firewall-cmd --permanent --zone="$zone" --add-source="$pod_cidr"
firewall-cmd --permanent --zone="$zone" --add-forward

# Permit only HTTPS egress plus DNS to OCI's link-local resolver. The ANY egress
# zone deliberately excludes HOST, so this policy cannot open node-local ports.
if ! firewall-cmd --permanent --get-policies | tr ' ' '\n' | grep -Fxq "$egress_policy"; then
  firewall-cmd --permanent --new-policy="$egress_policy"
  reload_required=true
fi
firewall-cmd --permanent --policy="$egress_policy" --set-target=CONTINUE
firewall-cmd --permanent --policy="$egress_policy" --add-ingress-zone="$zone"
firewall-cmd --permanent --policy="$egress_policy" --add-egress-zone=ANY
firewall-cmd --permanent --policy="$egress_policy" --add-port=443/tcp
firewall-cmd --permanent --policy="$egress_policy" \
  --add-rich-rule="rule family=ipv4 destination address=${oci_dns_resolver} port port=53 protocol=udp accept"
firewall-cmd --permanent --policy="$egress_policy" \
  --add-rich-rule="rule family=ipv4 destination address=${oci_dns_resolver} port port=53 protocol=tcp accept"

# Permit Prometheus pods to scrape the exact Kubernetes/node metric ports. The
# policy handles remote node addresses; matching zone ports handle the local node.
if ! firewall-cmd --permanent --get-policies | tr ' ' '\n' | grep -Fxq "$host_monitoring_policy"; then
  firewall-cmd --permanent --new-policy="$host_monitoring_policy"
  reload_required=true
fi
firewall-cmd --permanent --policy="$host_monitoring_policy" --set-target=CONTINUE
firewall-cmd --permanent --policy="$host_monitoring_policy" --add-ingress-zone="$zone"
firewall-cmd --permanent --policy="$host_monitoring_policy" --add-egress-zone=trusted
for port in "${monitoring_ports[@]}"; do
  firewall-cmd --permanent --zone="$zone" --add-port="${port}/tcp"
  firewall-cmd --permanent --policy="$host_monitoring_policy" --add-port="${port}/tcp"
done

firewall-cmd --check-config

# A reload is required only when creating firewalld objects for the first time.
# For existing objects, mirror permanent changes into runtime without flushing
# Kubernetes CNI hostPort and kube-proxy netfilter chains.
if [[ "$reload_required" == true ]]; then
  firewall-cmd --reload
  echo "New firewalld objects required a reload; restart hostPort workloads such as Traefik."
else
  firewall-cmd --zone="$zone" --add-source="$pod_cidr"
  firewall-cmd --zone="$zone" --add-forward
  firewall-cmd --policy="$egress_policy" --add-ingress-zone="$zone"
  firewall-cmd --policy="$egress_policy" --add-egress-zone=ANY
  firewall-cmd --policy="$egress_policy" --add-port=443/tcp
  firewall-cmd --policy="$egress_policy" \
    --add-rich-rule="rule family=ipv4 destination address=${oci_dns_resolver} port port=53 protocol=udp accept"
  firewall-cmd --policy="$egress_policy" \
    --add-rich-rule="rule family=ipv4 destination address=${oci_dns_resolver} port port=53 protocol=tcp accept"
  firewall-cmd --policy="$host_monitoring_policy" --add-ingress-zone="$zone"
  firewall-cmd --policy="$host_monitoring_policy" --add-egress-zone=trusted
  for port in "${monitoring_ports[@]}"; do
    firewall-cmd --zone="$zone" --add-port="${port}/tcp"
    firewall-cmd --policy="$host_monitoring_policy" --add-port="${port}/tcp"
  done
fi

firewall-cmd --zone="$zone" --query-source="$pod_cidr"
firewall-cmd --zone="$zone" --query-forward
firewall-cmd --policy="$egress_policy" --list-all
firewall-cmd --policy="$host_monitoring_policy" --list-all

echo "firewalld permits Canal forwarding, scoped egress, and monitoring scrapes for ${pod_cidr}."
