# Cluster production hardening

These resources cover controls outside the `localshops` namespace.

- `harden-control-plane.sh` enables Kubernetes Secret encryption at rest and bounded,
  metadata-focused API audit logging on the kubeadm control plane. The encryption key is
  generated on the control-plane host and is never committed to this repository.
- `etcd-backup.yaml` takes a six-hourly etcd snapshot, retains current and previous copies,
  and uses an encrypted Kubernetes Secret containing a read-only mounted backup client
  certificate. The job runs non-root.
- `keycloak-backup.yaml` writes a verified six-hourly Keycloak database dump to `node01`.
- `keycloak-network-policies.yaml` restricts Keycloak and its PostgreSQL service ingress.
- Network policy enforcement uses the version-pinned official Calico Canal deployment,
  with Flannel retaining VXLAN transport over `wg0` and Calico enforcing policy.
- `configure-firewalld-for-canal.sh` permanently allows only forwarded traffic whose
  source and destination are both inside the cluster pod CIDR. Run it as root on every
  node before or immediately after installing Canal. Without this scoped rule,
  firewalld classifies `cali*` workload interfaces as public and rejects direct endpoint
  traffic even when Calico NetworkPolicy allows it.
- `tune-grafana-vault-resources.sh` removes an unnecessary 250m Vault init-container CPU
  reservation that otherwise prevents Grafana from scheduling on `node01`. Reapply it
  after a monitoring Helm upgrade unless the same annotations are added to Helm values.
- `tune-traefik-native-lb.sh` makes Traefik use Kubernetes ClusterIP load balancing for
  Gateway API and Ingress backends. This preserves reliable cross-node routing through
  kube-proxy while Calico continues to enforce workload network policies. Reapply it after
  a Traefik Helm upgrade unless both native-LB settings are stored in Helm values.

## Canal host firewall prerequisite

Run this on every node. The command is idempotent and changes both the live and
persistent firewalld configuration without reloading the firewall:

```bash
sudo cluster/configure-firewalld-for-canal.sh
```

Validate the scoped rule and direct workload routing after all nodes are configured:

```bash
firewall-cmd --zone=public --list-rich-rules
kubectl get pods -A -o wide
```

Do not add the pod CIDR, public NIC, a wildcard `cali*` interface, or `0.0.0.0/0` to
the trusted zone. The script does not open pod-to-host access; Calico remains
responsible for workload policy enforcement before firewalld handles forwarding.

## Recovery boundary

The database copies on `node01` protect against loss of the application node (`node02`).
The etcd snapshots remain on the control-plane node. These copies reduce recovery time but
do not replace off-cluster disaster recovery.

Replicate all of the following to encrypted off-cluster storage:

- `/var/backups/etcd/etcd-current.db` and `etcd-previous.db`;
- `/etc/kubernetes/security/encryption-config.yaml`;
- the newest Localshops and Keycloak custom-format PostgreSQL dumps; and
- a separately protected copy of the Kubernetes PKI required by the documented kubeadm
  recovery procedure.

An etcd snapshot without its encryption provider key cannot decrypt Kubernetes Secrets.
OCI Object Storage credentials, bucket retention policy, and IAM policy are external
account resources and must never be committed here. Use a private bucket, a dedicated
write-only backup identity where practical, object versioning/retention, and quarterly
restore drills.

## Control-plane safety

Static-pod manifest backups belong in `/etc/kubernetes/manifest-backups`, never in
`/etc/kubernetes/manifests`; kubelet treats every file in the latter directory as a live
pod manifest. Take and validate an etcd snapshot before rerunning control-plane hardening.
