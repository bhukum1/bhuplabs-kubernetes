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
- OKE Secret `monitoring/observability-ingest` — ingestion password only.

All files must be root-owned mode `0600`. The original bootstrap credential can
remain in a root-only offline recovery file, but it is not mounted into any
container.

## Apply

Run from this directory with Ansible Core; no external Ansible collection is
required:

```bash
ansible-playbook site.yml
```

The playbook validates the disk, installs only the small required package set,
copies configuration and Quadlets, opens HTTP/HTTPS in firewalld, starts every
service, and waits for all local health endpoints.

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
