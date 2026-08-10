#!/usr/bin/env bash
set -euo pipefail

readonly target_file="/etc/sysctl.d/99-kubernetes-inotify.conf"
readonly target_instances="1024"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script as root on a Kubernetes node." >&2
  exit 1
fi

current_instances="$(sysctl -n fs.inotify.max_user_instances)"
effective_instances="${target_instances}"

if (( current_instances > target_instances )); then
  effective_instances="${current_instances}"
fi

if (( current_instances < target_instances )); then
  sysctl -w "fs.inotify.max_user_instances=${target_instances}"
fi

temporary_file="$(mktemp /etc/sysctl.d/.99-kubernetes-inotify.XXXXXX)"
trap 'rm -f "${temporary_file}"' EXIT

printf '%s\n' \
  '# Managed by bhuplabs-kubernetes/cluster/configure-node-inotify.sh' \
  '# Prevent kubelet log followers from exhausting per-user inotify instances.' \
  "fs.inotify.max_user_instances = ${effective_instances}" \
  >"${temporary_file}"
chmod 0644 "${temporary_file}"
mv "${temporary_file}" "${target_file}"
trap - EXIT

actual_instances="$(sysctl -n fs.inotify.max_user_instances)"
if (( actual_instances < target_instances )); then
  echo "Expected fs.inotify.max_user_instances to be at least ${target_instances}, got ${actual_instances}." >&2
  exit 1
fi

echo "fs.inotify.max_user_instances=${actual_instances} (persistent in ${target_file})"
