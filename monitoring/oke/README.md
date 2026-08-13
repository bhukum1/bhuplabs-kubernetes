# OKE monitoring collectors

The private OKE cluster runs only lightweight collectors. Durable metrics,
logs, dashboards and alerts remain on node02.

Pinned charts:

- Metrics Server `3.13.1` (application `0.8.1`)
- kube-state-metrics `8.2.0` (application `2.19.1`)
- prometheus-node-exporter `4.56.1` (application `1.12.1`)
- Grafana Alloy `1.11.1` (application `1.18.1`)

Alloy collects kubelet/cAdvisor, node, workload, Traefik, Localshops API and
Kubernetes-event metrics. It ships selected Localshops, Traefik, cert-manager
and monitoring logs to node02; successful health/metrics request logs are
dropped before transmission.

The ingestion password must be supplied as the existing Kubernetes Secret
`monitoring/observability-ingest`. Never put it in a values file.

```bash
helm upgrade --install metrics-server metrics-server/metrics-server \
  --version 3.13.1 -n kube-system -f metrics-server-values.yaml

helm upgrade --install kube-state-metrics prometheus-community/kube-state-metrics \
  --version 8.2.0 -n monitoring -f kube-state-metrics-values.yaml

helm upgrade --install node-exporter prometheus-community/prometheus-node-exporter \
  --version 4.56.1 -n monitoring -f node-exporter-values.yaml

kubectl apply -f application-network-policies.yaml

helm upgrade --install alloy grafana/alloy \
  --version 1.11.1 -n monitoring -f alloy-values.yaml
```

Verify:

```bash
kubectl get pods -n monitoring
kubectl top nodes
kubectl top pods -n monitoring
kubectl logs -n monitoring deploy/alloy -c alloy --since=10m
```
