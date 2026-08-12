# Migration data scope

There are no real shops or customers on the current platform. Existing shops,
products, orders, identities, sessions and notification subscriptions are test
data and will not be migrated.

## Preserve

- Git history and source-controlled application/infra configuration.
- PostgreSQL schema represented by Alembic migrations.
- Grafana dashboards, alert rules and log/metric configuration that remain
  relevant to the target architecture.
- DNS record inventory and certificate hostname list (never private keys).
- Terraform state in OCI Resource Manager after the new stack is created.
- A new, out-of-band platform administrator bootstrap procedure.
- A restore-tested backup of the new PostgreSQL database after bootstrap.

## Recreate from clean state

- Application PostgreSQL database and roles.
- Platform administrator account and recovery codes.
- SOPS/age keys, session signing material, webhook secrets and VAPID keys.
- Flux bootstrap credentials and OCIR pull credentials.
- Grafana administrator/SSO configuration.

## Explicitly discard

- All test shops, products, inventory, orders and customers.
- Keycloak, its PostgreSQL database, realms, clients, users and secrets.
- n8n, workflows, credentials and its PostgreSQL database.
- Redis contents and old application/session/rate-limit data.
- Vault Raft data, unseal keys, policies and tokens.
- Existing Prometheus/Loki/Tempo data and local Kubernetes PV contents.
- Existing browser-push subscriptions. Rotating VAPID keys is acceptable.

## Destruction gate

The kubeadm cluster may be removed only after a clean deployment has passed the
functional, security, observability, backup/restore and DNS cutover checks. A
destroy operation requires a separately reviewed target inventory and explicit
operator approval at the maintenance window.
