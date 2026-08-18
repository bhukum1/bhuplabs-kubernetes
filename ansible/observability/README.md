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
- PostgreSQL exporters run beside the DEV and production databases in OKE;
  Alloy forwards their dependency metrics to this control plane.

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
- `/etc/localshops-observability/alertmanager-smtp.json` — SMTP endpoint,
  sender, destination and generated OCI SMTP username;
- `/etc/localshops-observability/alertmanager-smtp-password` — generated OCI
  SMTP password, mounted read-only into Alertmanager;
- OKE Secret `monitoring/observability-ingest` — ingestion password only.

Runtime metadata files must be root-owned mode `0600`. The SMTP password may be
root-owned mode `0640` with group ID `65534` so only the rootful Alertmanager
container's unprivileged user can read the bind mount. The original bootstrap
credential can remain in a root-only offline recovery file, but it is not
mounted into any container.

Each application namespace holds a runtime-only `postgres-monitor` Secret for a
dedicated `localshops_monitor` login granted only the built-in `pg_monitor`
role. The Secret and password are never committed to Git.

## Apply

Run from this directory with Ansible Core; no external Ansible collection is
required:

```bash
ansible-playbook site.yml
```

The playbook validates the disk, installs only the small required package set,
copies configuration and Quadlets, opens HTTP/HTTPS in firewalld, starts every
service, and waits for all local health endpoints. It also disables the unused
PCP and RPC services, requires key-only SSH through the `opc` account, denies
root login, keeps every monitoring listener except Caddy on loopback, enforces
SELinux, and installs security-only package updates daily without automatic
reboots.

A daily systemd timer creates an atomic, integrity-checked Grafana SQLite backup
and an Alertmanager state archive under `/var/backups/localshops-observability`
on the separate boot volume. Seven days are retained and total recovery data is
capped at 1 GiB. Metric/log history is intentionally not duplicated locally:
its configuration is reproducible from Git and local duplication would waste
the Always Free disk without protecting against VM loss.

The backup publishes its last-success time and retained size through the
node-exporter textfile collector. vmalert raises a critical alert if no verified
observability backup succeeds for 36 hours. It also alerts when the OKE database
backup or weekly restore verification becomes stale, a recovery Job fails, or a
PostgreSQL volume falls below 15% free space.

Alertmanager sends production and infrastructure notifications through OCI
Email Delivery. Critical production alerts repeat hourly and warnings repeat
every four hours. DEV and legacy endpoint alerts use a separate receiver and
repeat at most once per 24 hours. Both receivers send a resolution email.

Bootstrap the two runtime files after creating the OCI SMTP credential. Keep
the JSON file root-owned mode `0600`; keep the password root-owned, group
`65534`, mode `0640`. The JSON document has this schema and must not be
committed:

```json
{
  "smarthost": "smtp.email.ap-hyderabad-1.oci.oraclecloud.com:587",
  "from": "alerts@dukly.in",
  "to": "operator@example.com",
  "auth_username": "generated OCI SMTP username"
}
```

Use a dedicated OCI identity with only the `SMTP credentials` capability. The
`localshops-email-senders` group is limited to the approved sender with this
tenancy policy:

```text
Allow group localshops-email-senders to use approved-senders in tenancy where target.approved-sender.emailaddress = 'alerts@dukly.in'
```

OCI Email Delivery also requires the `dukly.in` DNS zone to publish the
region-specific SPF record and the DKIM CNAME generated for the email domain.
Alertmanager can authenticate and send before DNS validation completes, but
delivery and spam placement are not production-ready until both records resolve.

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
