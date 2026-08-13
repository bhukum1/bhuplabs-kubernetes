# Observability VM automation

This directory will configure the secondary-tenancy Oracle Linux VM with
Ansible and rootless Podman/systemd units.

The following production inputs were verified on 2026-08-13:

- host: `node02` (`129.213.71.249`), Oracle Linux 9 on A1 Flex (2 OCPU/12 GB);
- data volume: 100 GiB OCI Always Free Block Volume, Balanced performance;
- attachment: paravirtualized read/write with in-transit encryption;
- filesystem: XFS mounted at `/srv/localshops-observability` by UUID;
- mount safety: `nofail`, `_netdev`, `noatime` and a 30-second device timeout.

The stack remains intentionally gated until the Grafana and ingestion DNS
records, alert receiver, firewall source CIDRs and pinned image digests are
confirmed. No secrets belong in inventory or group variables.

Runtime credentials will be SOPS-encrypted in Git and decrypted only on the
operator machine/target host.

The first runnable playbook will be delivered with these idempotent stages:

1. OS patching, chrony, firewall and SSH hardening.
2. Data-volume validation and directory ownership (never format an unknown
   device automatically).
3. Rootless Podman/systemd service installation with resource limits.
4. Caddy TLS routes, metrics/log ingestion authentication and Grafana access.
5. Local retention limits, backup jobs and restore verification.
6. Health checks from both the VM and an external endpoint.
