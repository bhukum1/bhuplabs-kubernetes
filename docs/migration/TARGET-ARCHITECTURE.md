# Target pilot architecture

## Primary tenancy: customer-facing OKE

- OKE Basic, two private A1 workers (1 OCPU / 6 GB each).
- Traefik, cert-manager, Flux, SOPS decryption and Calico policy enforcement.
- Next.js storefront/console, FastAPI, PostgreSQL and notification worker.
- Native PostgreSQL-backed owner/admin authentication; anonymous customers.
- One 10-Mbps Always Free public load balancer for application hostnames.
- OCI Object Storage for encrypted PostgreSQL backups and selected durable
  artifacts within the Always Free allowance.

Keycloak, Redis, Vault, n8n, Tempo and the monitoring UI do not run in OKE.

## Secondary tenancy: observability VM

The existing 2-OCPU / 12-GB A1 VM runs rootless Podman services managed by
systemd:

- Caddy as the only Internet-facing entry point.
- Grafana, VictoriaMetrics, vmalert, Loki, Alertmanager and Blackbox Exporter.
- Encrypted backup receiver/staging area on the data volume.

Only TCP 22, 80 and 443 are candidates for public ingress. SSH is restricted to
the operator CIDR; 80 is redirect/ACME only; 443 is protected per endpoint.
Metrics, logs and backups sent from OKE use TLS, per-service credentials and
source restrictions. Grafana is never exposed with a default password.

## Failure-domain reality

Two OKE workers improve scheduling and maintenance behavior but do not make the
database highly available. The zero-cost pilot accepts a bounded recovery
window: PostgreSQL runs as a single primary with persistent storage and frequent
encrypted off-host backups. Recovery is operationally tested. True database HA,
multi-region failover and fully redundant observability require paid resources.
