# Observability VM automation

This directory will configure the secondary-tenancy Oracle Linux VM with
Ansible and rootless Podman/systemd units. It is intentionally not runnable yet:
the VM identity, public IP, attached data-volume mount, firewall source CIDRs,
DNS names, alert receiver and pinned image digests must be confirmed first.

No secrets belong in inventory or group variables. Runtime credentials will be
SOPS-encrypted in Git and decrypted only on the operator machine/target host.

The first runnable playbook will be delivered with these idempotent stages:

1. OS patching, chrony, firewall and SSH hardening.
2. Data-volume validation and directory ownership (never format an unknown
   device automatically).
3. Rootless Podman/systemd service installation with resource limits.
4. Caddy TLS routes, metrics/log ingestion authentication and Grafana access.
5. Local retention limits, backup jobs and restore verification.
6. Health checks from both the VM and an external endpoint.
