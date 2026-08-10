#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script as root on the control-plane node." >&2
  exit 1
fi

manifest_dir=/etc/kubernetes/manifests
backup_dir=/etc/kubernetes/manifest-backups
control_plane_ip="${CONTROL_PLANE_IP:-10.0.0.250}"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"

for manifest in kube-controller-manager.yaml kube-scheduler.yaml etcd.yaml; do
  test -f "${manifest_dir}/${manifest}"
done

install -d -m 0700 "$backup_dir"
for manifest in kube-controller-manager.yaml kube-scheduler.yaml etcd.yaml; do
  cp -a "${manifest_dir}/${manifest}" "${backup_dir}/${manifest%.yaml}-metrics-${stamp}.yaml"
done

python3 - "$manifest_dir" "$backup_dir" "$control_plane_ip" <<'PY'
import os
import pathlib
import sys

manifest_dir = pathlib.Path(sys.argv[1])
backup_dir = pathlib.Path(sys.argv[2])
control_plane_ip = sys.argv[3]

replacements = {
    "kube-controller-manager.yaml": (
        "    - --bind-address=127.0.0.1\n",
        f"    - --bind-address={control_plane_ip}\n",
    ),
    "kube-scheduler.yaml": (
        "    - --bind-address=127.0.0.1\n",
        f"    - --bind-address={control_plane_ip}\n",
    ),
    "etcd.yaml": (
        "    - --listen-metrics-urls=http://127.0.0.1:2381\n",
        f"    - --listen-metrics-urls=http://127.0.0.1:2381,http://{control_plane_ip}:2381\n",
    ),
}

for name, (old, new) in replacements.items():
    path = manifest_dir / name
    text = path.read_text()
    original = text
    if new not in text:
        if old not in text:
            raise SystemExit(f"expected metrics binding not found in {path}")
        text = text.replace(old, new, 1)

    if name in {"kube-controller-manager.yaml", "kube-scheduler.yaml"}:
        # The kubeadm probes default to loopback. Keep them aligned with the
        # private-only listener so kubelet does not report false failures.
        text = text.replace(
            "        host: 127.0.0.1\n",
            f"        host: {control_plane_ip}\n",
        )

    updated = text
    if updated == original:
        continue
    temporary = backup_dir / f"{name}.metrics.new"
    temporary.write_text(updated)
    os.chmod(temporary, path.stat().st_mode)
    os.replace(temporary, path)
PY

echo "Control-plane metric listeners updated on ${control_plane_ip}; kubelet will restart the static pods."
echo "Backups are in ${backup_dir} and must remain outside ${manifest_dir}."
