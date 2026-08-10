# Bhuplabs Kubernetes platform

Git-safe source for the deployed Bhuplabs platform:

- Kubernetes 1.34.9
- Traefik 3.7.6, Helm chart 41.0.2
- cert-manager 1.21.0
- Gateway API 1.5.1
- kube-prometheus-stack 87.19.0
- HashiCorp Vault Community 2.0.3, Helm chart 0.34.0
- Keycloak 26.7.0 with PostgreSQL 16
- oauth2-proxy 7.15.2
- n8n 2.31.5
- PostgreSQL 16
- NGINX chatbot frontend

No live credentials, Vault bootstrap material, TLS private keys, or Kubernetes
Secret exports are included.

## Repository layout

```text
cluster/       Cluster hardening, CNI, backups, node storage, and operational tuning
cert-manager/  ACME issuer and chart values
monitoring/    Grafana/Prometheus storage and Helm values
n8n/           n8n, PostgreSQL, Vault injection, workflows, and chatbot frontend
keycloak/      Keycloak, PostgreSQL, TLS, and SSO operational notes
storage/       local Retain storage class
traefik/       production values, health backend, Gateways, and routes
vault/         Raft storage, chart values, policies, routes, and scripts
docs/          architecture and operational notes
```

Cluster-wide controls and repeatable post-upgrade tuning live in `cluster/`. Read
`cluster/README.md` before changing the control plane, CNI, backup jobs, or shared
component scheduling.

## Prerequisites

- DNS A records for `n8n`, `grafana`, `vault`, and `auth.bhuplabs.dev` pointing to
  `140.245.252.229`.
- TCP 80 and 443 forwarded to `master` and/or `node01`.
- `kubectl`, `jq`, `xxd`, and macOS Keychain's `security` command.
- A current Helm client with Go-template `break`/`continue` support. Helm 3.6 is
  too old for the pinned Traefik chart.
- Local directories prepared on the pinned nodes:

```text
node01: /var/lib/n8n
node01: /var/lib/n8n-postgres
node01: /var/lib/grafana
node02: /var/lib/vault (UID 100, GID 1000)
master: /var/lib/keycloak-postgres (UID 999, GID 999)
```

## Installation order

Install the Gateway API CRDs and local storage class:

```bash
kubectl apply -f \
  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
kubectl apply -f storage/local-retain.yaml
```

Install cert-manager:

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.21.0 \
  --values cert-manager/values.yaml
kubectl apply -f cert-manager/cluster-issuer.yaml
```

Install Traefik:

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --version 41.0.2 \
  --values traefik/values.yaml
kubectl apply -f traefik/health-backend.yaml
```

Install and initialize Vault:

```bash
kubectl apply -f vault/storage.yaml
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm upgrade --install vault hashicorp/vault \
  --namespace vault \
  --version 0.34.0 \
  --values vault/values.yaml
vault/scripts/initialize.sh
vault/scripts/configure.sh
vault/scripts/seed-n8n-secrets.sh
kubectl apply -f vault/public-route.yaml
```

Deploy n8n and its chatbot frontend:

```bash
kubectl apply -f n8n/platform.yaml
kubectl apply -f n8n/chatbot-web.yaml
```

The workflow-only export is at `n8n/workflows/workflows.json`. It intentionally
does not include n8n credential bodies. See `n8n/workflows/README.md` before
importing it into another instance.

Deploy Keycloak after its database, bootstrap, user, and client secrets have
been seeded in Vault as described in `keycloak/README.md`:

```bash
kubectl apply -f keycloak/platform.yaml
kubectl apply -f keycloak/public-route.yaml
kubectl apply -f n8n/oauth2-proxy.yaml
kubectl apply -f traefik/application-routes.yaml
```

The n8n editor and API are protected by Keycloak. Production/test webhooks and
n8n Form endpoints bypass interactive login so external automations can call
them. Access control for those public endpoints must be implemented in the
workflow itself.

Install monitoring after creating `monitoring/grafana-admin` through a secure,
out-of-band process:

```bash
kubectl apply -f monitoring/storage.yaml
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install kps \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --version 87.19.0 \
  --values monitoring/values.yaml
helm upgrade kps prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --version 87.19.0 \
  --reuse-values \
  --values monitoring/grafana-sso-values.yaml
kubectl apply -f traefik/application-routes.yaml
```

## Validation

```bash
kubectl get pods -A
kubectl get gateway,httproute -A
kubectl get certificate -A
kubectl apply -f vault/injection-smoke-test.yaml
kubectl logs -n n8n vault-injection-smoke-test
curl -I https://n8n.bhuplabs.dev/
curl -I https://grafana.bhuplabs.dev/
curl -I https://vault.bhuplabs.dev/ui/
curl -I https://auth.bhuplabs.dev/
```

An unauthenticated request to `https://n8n.bhuplabs.dev/` should redirect to
Keycloak. A production webhook returns n8n's normal response without an SSO
redirect; it returns 404 until its workflow is active.

## Vault recovery and backup

Bootstrap data is stored under the macOS Keychain service
`bhuplabs-vault-bootstrap`. It is deliberately absent from Git.

```bash
vault/scripts/unseal-from-keychain.sh
vault/scripts/raft-snapshot.sh /secure/off-cluster/vault-raft.snap
```

Raft snapshots contain sensitive encrypted state. Keep them outside this
repository with restrictive permissions.
