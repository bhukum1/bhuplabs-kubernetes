# OKE cluster add-ons

## Calico policy enforcement

OKE uses OCI VCN-native pod networking. Kubernetes `NetworkPolicy` resources require a separate enforcement engine, so this cluster runs Calico in policy-only mode. Calico does not install or replace the OCI CNI.

The installer pins Calico `v3.32.0`, validates both the official source and rendered OCI-specific manifest by SHA-256, performs a server-side dry run, and only changes the cluster when explicitly enabled.

```bash
export KUBECONFIG=/home/opc/.kube/localshops-production
./install-calico-policy-only.sh
APPLY=true ./install-calico-policy-only.sh
```

The OCI-specific patch follows Oracle's VCN-native Calico guidance: it removes CNI installation, selects `oci` workload interfaces, disables Calico IP pools and BGP networking, appends policy chains, and uses nftables on the Oracle Linux 8 workers.

Do not apply application default-deny policies until all Calico workloads are Ready and a disposable pod has passed DNS, external HTTPS, and standalone PostgreSQL connectivity checks.
