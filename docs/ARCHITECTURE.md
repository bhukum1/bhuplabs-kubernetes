# Architecture

Traffic for `n8n.bhuplabs.dev`, `grafana.bhuplabs.dev`,
`vault.bhuplabs.dev`, and `auth.bhuplabs.dev` resolves to
`140.245.252.229`. The external load
balancer forwards TCP 80 and 443 to the Kubernetes nodes running Traefik.

Traefik uses Kubernetes Gateway API resources and terminates certificates
issued by cert-manager. The internal Vault listener is HTTP-only; Vault UI
traffic is encrypted between the client and Traefik.

n8n and PostgreSQL authenticate to Vault with their Kubernetes service
accounts. The Vault Agent Injector adds an init container and a memory-backed
volume to each pod:

```text
Kubernetes ServiceAccount JWT
    -> Vault Kubernetes auth
    -> bounded Vault role and policy
    -> Vault Agent init container
    -> /vault/secrets/*
    -> application startup environment
```

The injection mode is `agent-pre-populate-only`. A secret rotation therefore
requires restarting the affected workload:

```bash
kubectl rollout restart deployment/n8n -n n8n
kubectl rollout restart statefulset/n8n-postgres -n n8n
```

Vault is a single Raft member pinned to `node02`. This is not HA despite using
Vault's HA/Raft server mode. Its persistent volume uses `/var/lib/vault` on
`node02`. Use a dedicated external VM or managed Vault service if the Vault
failure domain must be outside the Kubernetes cluster.

Grafana's existing admin credential has not yet been migrated to Vault.
Prometheus Operator, cert-manager, Helm, TLS, and webhook certificate Secrets
are Kubernetes/controller-managed and remain in Kubernetes.

Keycloak and its dedicated PostgreSQL database are pinned to `master`.
Application credentials are stored in Vault and rendered into memory by Vault
Agent. Keycloak is the OIDC identity provider for:

```text
Keycloak
  -> Grafana Generic OAuth (native)
  -> Vault OIDC auth (default policy only)
  -> oauth2-proxy -> n8n editor/API
```

This small installation uses Keycloak's required `master` realm for both
administration and application SSO, with a single `admin` user. This reduces
account duplication but also reduces privilege separation. Reintroduce a
dedicated application realm before adding less-trusted users.

Gateway API routes send n8n `/webhook*` and `/form*` paths directly to n8n.
The catch-all route sends all other HTTPS traffic to oauth2-proxy, which
requires a Keycloak session before proxying to n8n.
