# DUKLY production operations runbook

Last verified: 2026-08-18

This runbook covers the zero-cost DUKLY pilot running on private OKE in
`ap-hyderabad-1`, with node02 providing cluster access and the external
observability stack. It contains no credentials.

## Service objectives and accepted constraints

- Pilot scope: up to 20 small shops while real traffic is measured.
- Database recovery point objective: less than 24 hours. PostgreSQL is dumped
  daily at 02:30 Asia/Kolkata to the private `dukly-db-backups` Object Storage
  bucket and objects are retained for 30 days.
- Recovery time target: four hours for an operator-led database restore.
- API and web each run two replicas spread across the two OKE workers.
- PostgreSQL is a single instance on an OCI Block Volume with `Retain` reclaim
  policy. This protects data from pod and node replacement but is not database
  high availability.
- One worker can continue serving the customer web and owner application, but
  current Always Free CPU capacity cannot reschedule every cluster workload to
  one node. A controlled drain on 2026-08-18 produced a brief API readiness
  failure before recovery. Do not advertise zero-downtime node failover.
- node02 and its local observability volume are single-instance components.
  Their failure removes dashboards and log search, not the OKE application.

## Access

SSH to node02 using the operator key:

```bash
ssh opc@129.213.71.249
```

Start or verify the private OKE tunnel, then use the local kubeconfig:

```bash
/usr/local/bin/oke-connect
export KUBECONFIG=/home/opc/.kube/config
kubectl get nodes
```

Keep OKE private. Do not publish the Kubernetes API or copy a long-lived
kubeconfig to unmanaged machines.

## Routine health check

```bash
kubectl get nodes
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
kubectl -n localshops get deploy,statefulset,cronjob
kubectl top nodes

curl -fsS https://api.dukly.in/health/ready
curl -fsS https://dukly.in/ >/dev/null
curl -fsS https://app.dukly.in/ >/dev/null
curl -fsS https://grafana.bhuplabs.dev/api/health
curl -fsS https://observe.bhuplabs.dev/health
```

On node02, all observability services should be active:

```bash
systemctl list-units --type=service --state=running 'localshops-*'
curl -fsS http://127.0.0.1:8429/api/v1/targets | jq \
  '{total:(.data.activeTargets|length),up:([.data.activeTargets[]|select(.health=="up")]|length)}'
curl -fsS http://127.0.0.1:9093/api/v2/alerts | jq length
```

## Release and rollback

Production images are pinned by immutable OCIR digest in
`localshops-gitops/apps/localshops/production/kustomization.yaml`. Never deploy
`latest` or another mutable tag.

Before a production release:

1. Confirm the image passed build, test and vulnerability scanning.
2. Record the current API and web digests.
3. Review the manifest diff and migration Job.
4. Push the reviewed Git commit, wait for `localshops-production` to become
   Ready, and confirm both Deployments are available.
5. Run the public health checks and one read-only shop/storefront request.

Rollback by restoring the previous known-good API and web digests in Git and
reapplying that reviewed revision. Database migrations must be backward
compatible. Do not reverse a database migration automatically unless its
explicit downgrade path has been tested against a restored backup.

DEV and production are reconciled by Flux from `bhukum1/localshops-gitops`.
Production uses the `localshops-production` Kustomization and the
`./apps/localshops/production` path. Normal releases must change the immutable
digests in Git; do not patch live Deployments. Verify the applied revision with:

```bash
kubectl -n flux-system get kustomization localshops-production
```

## PostgreSQL backup verification

Check the schedules:

```bash
kubectl -n localshops get cronjob postgres-backup postgres-restore-check
```

Run an on-demand backup without changing application data:

```bash
job="postgres-backup-manual-$(date -u +%Y%m%d%H%M%S)"
kubectl -n localshops create job --from=cronjob/postgres-backup "$job"
kubectl -n localshops wait --for=condition=complete "job/$job" --timeout=5m
kubectl -n localshops logs "job/$job" --all-containers=true
```

Run the isolated restore verifier. It downloads the newest Object Storage dump,
checks its SHA-256 file, starts a temporary PostgreSQL instance on `emptyDir`,
restores the dump with `--exit-on-error`, and confirms public tables exist. It
does not connect to or overwrite production PostgreSQL.

```bash
job="postgres-restore-check-manual-$(date -u +%Y%m%d%H%M%S)"
kubectl -n localshops create job --from=cronjob/postgres-restore-check "$job"
kubectl -n localshops wait --for=condition=complete "job/$job" --timeout=5m
kubectl -n localshops logs "job/$job" --all-containers=true
```

The 2026-08-18 drill restored 12 public tables from a fresh verified dump.

## Database incident recovery

For suspected corruption, stop writes before attempting recovery:

1. Put the storefront into maintenance mode or disable checkout.
2. Scale `api` and `notification-worker` to zero.
3. Preserve the existing PVC and Block Volume; never delete it during initial
   diagnosis.
4. Run the isolated restore verifier against the newest backup.
5. Restore into a new temporary PVC/database and validate schema and row counts.
6. Point the application Secret at the recovered database only after validation.
7. Start one API replica, run health and order-read checks, then restore normal
   replicas and workers.

Treat deletion of a PVC, PV, Block Volume, Object Storage object, or database as
a separate destructive change requiring explicit approval and a verified backup.

## Worker-node incident

For a planned test or maintenance window, choose the node that does not host
`postgres-0`:

```bash
kubectl -n localshops get pod postgres-0 -o wide
kubectl cordon NODE
kubectl drain NODE --ignore-daemonsets --delete-emptydir-data \
  --grace-period=30 --timeout=3m
```

Probe the three public endpoints while degraded. Restore scheduling immediately:

```bash
kubectl uncordon NODE
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
```

If a DaemonSet pod remains Pending because the surviving node is CPU-saturated,
move one restartable DEV pod back to the recovered node. Do not evict
`localshops/postgres-0` as an ad-hoc test.

## Terraform and OCI network changes

The production stack is `localshops-oke-production` in OCI Resource Manager.
Always upload a committed repository archive, run a plan, review every action,
and apply the saved plan. A second plan must report:

```text
No changes. Your infrastructure matches the configuration.
```

The public load balancer must retain its dedicated NSG. Only TCP 80 and 443 are
internet-facing through that NSG and the shared default security list. Do not
restore broad protocols, Kubernetes API, etcd, kubelet, SSH, WireGuard, or
NodePort access from `0.0.0.0/0`.

## Monitoring and alerting

- Grafana: `https://grafana.bhuplabs.dev`
- Protected ingest health: `https://observe.bhuplabs.dev/health`
- Alertmanager and all raw metrics/log endpoints bind to loopback on node02.
- The root of `observe.bhuplabs.dev` intentionally returns 404; it is not a
  public dashboard.

Alertmanager currently groups and retains alerts locally. Configure one
out-of-band external receiver before real-shop onboarding, then inject a test
alert and confirm both firing and resolved notifications arrive.

## Credential rotation

Rotate OCIR publisher/pull tokens, Object Storage S3-compatible keys, platform
administrator credentials, database credentials and VAPID keys independently.
Store values only in GitHub environment secrets or Kubernetes Secrets created
out of band. After each rotation, restart only the consuming workload and
verify health before revoking the old credential.

Never print Secret values into CI logs, shell history, Git commits, support
tickets or this runbook.

## 2026-08-18 readiness evidence

- OCI Resource Manager post-apply plan: zero changes.
- PostgreSQL fresh backup upload: passed.
- SHA-256 verification and isolated restore: passed, 12 public tables.
- Controlled non-database worker drain: web remained available; API had a brief
  readiness failure; full cluster recovery passed.
- Load test: 1,000 shop-directory plus 1,000 storefront requests at concurrency
  20; 2,000/2,000 HTTP 200, p95 0.641s and 0.756s respectively, no API 5xx.
- Monitoring after test: 20/20 targets up and zero active alerts.
