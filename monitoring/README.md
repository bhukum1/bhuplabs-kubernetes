# In-cluster observability

This stack keeps metrics, logs, traces, dashboards, and alert evaluation inside
the Kubernetes cluster. Only Grafana is exposed publicly, through the existing
TLS and Keycloak SSO configuration.

## Components and retention

| Component | Purpose | Local storage | Retention |
| --- | --- | ---: | ---: |
| Prometheus | Infrastructure and application metrics | 4 GiB on `node02` | 7 days, capped at 3.5 GB |
| Alertmanager | Alert grouping and silences | 512 MiB on `node02` | 5 days |
| Grafana | Dashboards and Explore | Existing 5 GiB on `node01` | Configuration database |
| Loki | Kubernetes and application logs | 4 GiB on `node01` | 72 hours |
| Tempo | OTLP traces | 2 GiB on `node02` | 24 hours |
| Alloy | Per-node log collector and OTLP gateway | Ephemeral | Not applicable |
| Blackbox exporter | Cluster-local service health and response-time probes | None | Stored in Prometheus |

All PVs use `local-retain`. Deleting a Helm release or PVC does not delete its
underlying data, but local storage is not highly available and is not a backup.
The workloads are pinned through PV node affinity. A failed node therefore
requires node recovery or a deliberate restore/migration.

## Install or upgrade

The chart versions are pinned to:

- kube-prometheus-stack `87.19.0`
- Loki `7.2.0`
- Tempo `1.24.4`
- Alloy `1.11.1`
- prometheus-blackbox-exporter `11.17.1`

Before installing the stack on firewalld-based nodes, apply the scoped Canal
forwarding prerequisite on every node. It creates a dedicated pod-CIDR zone
with intra-zone forwarding, HTTPS and OCI DNS egress, and only the node-local
ports required by Prometheus:

```bash
sudo cluster/configure-firewalld-for-canal.sh
```

Prometheus scrapes endpoint Pod IPs directly. A cluster where only ClusterIP
traffic works will otherwise show every target as down even though the
monitoring pods themselves are healthy.

The default kubeadm scheduler, controller-manager, etcd, and kube-proxy metric
listeners bind to loopback. After the firewall policy is active on every node,
enable their private listeners using the scripts documented in `cluster/README.md`.

The API ServiceMonitor currently scrapes `localshops-dev`. Production API health
is still checked through Blackbox, but its older image returns 404 on `/metrics`.
Add `localshops` to the ServiceMonitor namespace selector when the metrics-enabled
API image is promoted to production.

Prepare the host directories once, then create the Retain PVs:

```bash
kubectl apply -f monitoring/prepare-storage.yaml
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/monitoring-storage-prep-node01 pod/monitoring-storage-prep-node02 -n kube-system --timeout=120s
kubectl apply -f monitoring/storage.yaml
kubectl apply -f monitoring/storage-observability.yaml
```

Install the charts. The base and SSO values must be supplied together so an
upgrade cannot accidentally remove Grafana SSO:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace --version 87.19.0 \
  --values monitoring/values.yaml \
  --values monitoring/grafana-sso-values.yaml \
  --wait --timeout 10m

helm upgrade --install loki grafana/loki \
  --namespace monitoring --version 7.2.0 \
  --values monitoring/loki-values.yaml --wait --timeout 10m

helm upgrade --install tempo grafana/tempo \
  --namespace monitoring --version 1.24.4 \
  --values monitoring/tempo-values.yaml --wait --timeout 10m

helm upgrade --install alloy grafana/alloy \
  --namespace monitoring --version 1.11.1 \
  --values monitoring/alloy-values.yaml --wait --timeout 10m

helm upgrade --install blackbox prometheus-community/prometheus-blackbox-exporter \
  --namespace monitoring --version 11.17.1 \
  --values monitoring/blackbox-values.yaml --wait --timeout 10m
```

Apply monitors, dashboards, rules, and network policy after the workloads are
healthy:

```bash
kubectl apply -f monitoring/application-observability.yaml
kubectl apply -f monitoring/traefik-observability.yaml
kubectl apply -f monitoring/alert-rules.yaml
kubectl apply -f monitoring/dashboard-localshops.yaml
kubectl apply -f monitoring/dashboard-localshops-http.yaml
kubectl apply -f monitoring/network-policies.yaml
```

The storage preparation pods are intentionally one-shot. After they report
`Succeeded`, they may be deleted and recreated only when a new node directory
must be prepared.

## Access and alert delivery

Open `https://grafana.bhuplabs.dev` and sign in with Keycloak. Under
**Dashboards**, open **Localshops HTTP and API overview** for gateway and API
request rates, 2xx/3xx/4xx/5xx breakdowns, error percentages, latency, route
details, and related logs. **Localshops platform overview** remains the compact
health and operations dashboard. Cluster/app logs are searchable in
**Explore > Loki** with queries such as:

The dashboard's gateway panels include both production and development traffic.
The detailed FastAPI panels currently contain development data only; they will
include production automatically after the metrics-enabled API image is promoted
and `localshops` is added to the ServiceMonitor namespace selector.

```logql
{namespace="localshops-dev", app="api"}
{namespace=~"localshops(-dev)?"} |= "ERROR"
```

In Grafana, open **Explore**, select the **Loki** data source, paste a query,
choose a time range, and select **Run query**. Expand a row to see its namespace,
pod, container, and application labels.

Dev API logs:

```logql
{namespace="localshops-dev", app="api"}
```

Production API and web logs:

```logql
{namespace="localshops", app=~"api|web"}
```

Errors and exceptions across both environments:

```logql
{namespace=~"localshops(-dev)?", app=~"api|web"} |~ "(?i)(error|exception|traceback| 5[0-9]{2} )"
```

Order-related messages currently emitted by the API:

```logql
{namespace=~"localshops(-dev)?", app="api"} |~ "(?i)(order|checkout)"
```

The dashboard and collector omit successful health/metrics requests. Failed checks
remain visible and continue to generate metrics and alerts.

For immediate command-line troubleshooting without Loki:

```bash
kubectl logs -n localshops-dev deployment/api --since=30m -f
kubectl logs -n localshops-dev deployment/web --since=30m -f
kubectl logs -n localshops deployment/api --since=30m -f
```

Prometheus evaluates the rules and Alertmanager displays active alerts in
Grafana. The current receiver is deliberately `null`: external delivery is not
enabled until a notification credential and destination are supplied. Add one
receiver (SMTP, Slack, or a Telegram webhook) through a Kubernetes Secret or
Vault; never commit its token to this repository.

Blackbox probes currently use cluster-local service addresses. This reliably
detects failed apps, APIs, Keycloak, and Grafana without OCI public-IP hairpin
false positives. It does not validate public DNS, TLS, NAT, or the Internet path.
Use a genuinely external uptime checker for those tests; do not point an
in-cluster probe at the cluster's own OCI public IP. External alert delivery and
external uptime checks remain the two deliberate integrations requiring a
provider/destination choice.

## Validation

```bash
kubectl get pods,pvc -n monitoring
kubectl get servicemonitor,prometheusrule -n monitoring
kubectl logs -n monitoring daemonset/alloy -c alloy --tail=100
kubectl port-forward -n monitoring service/loki 3100:3100
curl -fsS http://127.0.0.1:3100/ready
```

Verify Prometheus targets from Grafana Explore with:

```promql
up
probe_success
localshops_http_requests_total
```

## Cost and migration

The software and current local PVCs add no cloud service charge. They consume
existing node CPU, memory, and disk. External alert channels may have provider
charges, although Telegram and many email/Slack plans can be used at no cost.

Before onboarding enough shops to generate sustained log volume, migrate Loki
and Tempo to OCI Object Storage and move Prometheus long-term retention to a
remote backend. Keep the local stack and short retention until that is needed;
do not pay for object storage blindly.
