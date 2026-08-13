# Node02 observability stack

This directory is the reproducible configuration for the Localshops monitoring
control plane on `node02` (`129.213.71.249`). It is deliberately separate from
OKE so a cluster outage does not remove its dashboards, logs, probes or alerts.

## Deployed components

- Caddy: public TLS and authenticated ingestion gateway.
- Grafana: dashboards and log exploration.
- VictoriaMetrics plus vmagent: retained metrics and local/public scrapes.
- Loki: application, ingress, monitoring and Kubernetes event logs.
- vmalert plus Alertmanager: evaluated alert rules and notification routing.
- Blackbox exporter: external HTTPS availability/latency probes.
- node-exporter: node02 CPU, memory, filesystem and network metrics.
- postgres-exporter: database availability, capacity, activity and deadlocks.

Grafana provisions five version-controlled dashboards: production overview,
HTTP/API status and latency, OKE/workloads, application logs, and PostgreSQL/
Redis dependencies.

Images are pinned by immutable multi-architecture digest. All data is stored on
the verified 100 GiB OCI Always Free XFS volume mounted at
`/srv/localshops-observability`. The playbook checks its UUID and will never
format or replace an unknown disk.

## Public DNS

Create these Namecheap BasicDNS records (TTL Automatic):

| Type | Host | Value |
|---|---|---|
| A | `grafana` | `129.213.71.249` |
| A | `observe` | `129.213.71.249` |

`grafana.bhuplabs.dev` is the human UI. `observe.bhuplabs.dev` accepts only the
authenticated VictoriaMetrics remote-write and Loki push paths. Caddy obtains
and renews public certificates automatically after DNS resolves.

## Runtime credentials

Secrets are deliberately absent from Git and inventory. The live host uses:

- `/etc/localshops-observability/grafana.env` — Grafana administrator only;
- `/etc/localshops-observability/caddy.env` — ingestion password hash only;
- `/etc/localshops-observability/postgres-exporter.env` — read-only database monitor only;
- OKE Secret `monitoring/observability-ingest` — ingestion password only.

All files must be root-owned mode `0600`. The original bootstrap credential can
remain in a root-only offline recovery file, but it is not mounted into any
container.

Create the `localshops_monitor` PostgreSQL login once, grant it only the built-in
`pg_monitor` role, and place its localhost DSN in `postgres-exporter.env`. The
playbook manages the exact localhost SCRAM pg_hba rule but deliberately does not
generate or rotate database credentials stored outside Git.

## Apply

Run from this directory with Ansible Core; no external Ansible collection is
required:

```bash
ansible-playbook site.yml
```

The playbook validates the disk, installs only the small required package set,
copies configuration and Quadlets, opens HTTP/HTTPS in firewalld, starts every
service, and waits for all local health endpoints.

A daily systemd timer creates an atomic, integrity-checked Grafana SQLite backup
and an Alertmanager state archive under `/var/backups/localshops-observability`
on the separate boot volume. Seven days are retained and total recovery data is
capped at 1 GiB. Metric/log history is intentionally not duplicated locally:
its configuration is reproducible from Git and local duplication would waste
the Always Free disk without protecting against VM loss.

The backup publishes its last-success time and retained size through the
node-exporter textfile collector. vmalert raises a critical alert if no verified
backup succeeds for 36 hours.

Alertmanager currently validates, groups and retains alerts locally. External
delivery is enabled only after a Telegram bot token/chat ID or SMTP destination
is supplied out of band. Keep those values in root-only files and use the
supported Alertmanager `*_file` fields; never add them to this repository.

## Useful checks

```bash
systemctl status 'localshops-*'
curl -fsS http://127.0.0.1:3000/api/health
curl -fsS http://127.0.0.1:8428/health
curl -fsS http://127.0.0.1:3100/ready
curl -fsS http://127.0.0.1:9093/-/ready
```

Grafana credentials can be read only by a node02 sudo administrator:

```bash
sudo sed -n 's/^GF_SECURITY_ADMIN_USER=//p' /etc/localshops-observability/grafana.env
sudo sed -n 's/^GF_SECURITY_ADMIN_PASSWORD=//p' /etc/localshops-observability/grafana.env
```
