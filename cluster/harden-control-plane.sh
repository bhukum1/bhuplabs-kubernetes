#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "run as root" >&2
  exit 1
fi

manifest=/etc/kubernetes/manifests/kube-apiserver.yaml
manifest_backup_dir=/etc/kubernetes/manifest-backups
security_dir=/etc/kubernetes/security
audit_dir=/var/log/kubernetes/audit
etcd_backup_dir=/var/backups/etcd
stamp="$(date -u +%Y%m%dT%H%M%SZ)"

test -f "$manifest"
install -d -m 0700 "$manifest_backup_dir"
install -d -m 0700 "$security_dir"
install -d -m 0700 "$audit_dir"
install -d -o 65534 -g 65534 -m 0700 "$etcd_backup_dir"
cp -a "$manifest" "${manifest_backup_dir}/kube-apiserver-${stamp}.yaml"

if [[ ! -f "${security_dir}/encryption-config.yaml" ]]; then
  umask 077
  encryption_key="$(head -c 32 /dev/urandom | base64)"
  printf '%s\n' \
    'apiVersion: apiserver.config.k8s.io/v1' \
    'kind: EncryptionConfiguration' \
    'resources:' \
    '  - resources:' \
    '      - secrets' \
    '    providers:' \
    '      - secretbox:' \
    '          keys:' \
    '            - name: key-2026-08' \
    "              secret: ${encryption_key}" \
    '      - identity: {}' >"${security_dir}/encryption-config.yaml"
fi
chmod 0600 "${security_dir}/encryption-config.yaml"

cat >"${security_dir}/audit-policy.yaml" <<'AUDIT'
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages:
  - RequestReceived
omitManagedFields: true
rules:
  - level: None
    users:
      - system:kube-proxy
    verbs: [watch]
  - level: None
    userGroups:
      - system:nodes
    verbs: [get]
    resources:
      - group: ""
        resources: [nodes, nodes/status]
  - level: None
    nonResourceURLs:
      - /healthz*
      - /livez*
      - /readyz*
      - /version
  - level: Metadata
    resources:
      - group: ""
        resources: [secrets, configmaps, serviceaccounts]
  - level: Request
    verbs: [create, update, patch, delete, deletecollection]
    resources:
      - group: ""
      - group: apps
      - group: batch
      - group: networking.k8s.io
      - group: rbac.authorization.k8s.io
  - level: Metadata
AUDIT
chmod 0600 "${security_dir}/audit-policy.yaml"

python3 - "$manifest" "$manifest_backup_dir" <<'PY'
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
backup_dir = pathlib.Path(sys.argv[2])
text = path.read_text()

flag_anchor = "    - --authorization-mode=Node,RBAC\n"
flags = (
    "    - --audit-log-maxage=10\n"
    "    - --audit-log-maxbackup=10\n"
    "    - --audit-log-maxsize=100\n"
    "    - --audit-log-path=/var/log/kubernetes/audit/audit.log\n"
    "    - --audit-policy-file=/etc/kubernetes/security/audit-policy.yaml\n"
    "    - --encryption-provider-config=/etc/kubernetes/security/encryption-config.yaml\n"
    "    - --encryption-provider-config-automatic-reload=true\n"
)
if "--encryption-provider-config=" not in text:
    if flag_anchor not in text:
        raise SystemExit("authorization flag anchor not found")
    text = text.replace(flag_anchor, flag_anchor + flags, 1)

mount_anchor = (
    "    - mountPath: /etc/kubernetes/pki\n"
    "      name: k8s-certs\n"
    "      readOnly: true\n"
)
mounts = (
    "    - mountPath: /etc/kubernetes/security\n"
    "      name: security-config\n"
    "      readOnly: true\n"
    "    - mountPath: /var/log/kubernetes/audit\n"
    "      name: audit-log\n"
    "      readOnly: false\n"
)
if "name: security-config" not in text:
    if mount_anchor not in text:
        raise SystemExit("volume mount anchor not found")
    text = text.replace(mount_anchor, mount_anchor + mounts, 1)

volume_anchor = (
    "  - hostPath:\n"
    "      path: /etc/kubernetes/pki\n"
    "      type: DirectoryOrCreate\n"
    "    name: k8s-certs\n"
)
volumes = (
    "  - hostPath:\n"
    "      path: /etc/kubernetes/security\n"
    "      type: Directory\n"
    "    name: security-config\n"
    "  - hostPath:\n"
    "      path: /var/log/kubernetes/audit\n"
    "      type: DirectoryOrCreate\n"
    "    name: audit-log\n"
)
if "      path: /var/log/kubernetes/audit\n      type: DirectoryOrCreate" not in text:
    if volume_anchor not in text:
        raise SystemExit("volume anchor not found")
    text = text.replace(volume_anchor, volume_anchor + volumes, 1)

temporary = backup_dir / "kube-apiserver.yaml.new"
temporary.write_text(text)
os.chmod(temporary, path.stat().st_mode)
os.replace(temporary, path)
PY

echo "Control-plane hardening installed; kubelet will restart kube-apiserver."
