# LocalShops OKE foundation

This stack creates the primary-tenancy pilot platform with a deliberate hard
cost boundary:

- OKE **Basic** cluster with a private Kubernetes API endpoint.
- VCN-native pod networking in dedicated subnets within an existing VCN.
- Two private `VM.Standard.A1.Flex` workers, each 1 OCPU / 6 GB RAM / 50 GB
  boot volume.
- Reuse of the existing Always Free load-balancer subnet and public IP, with
  private worker/pod/control-plane subnets plus NAT and OCI service gateways.
- An optional, narrowly scoped route to the existing WireGuard gateway for
  node02 services while cross-tenancy DRG peering is completed.
- No bastion VM, operator VM, paid worker fallback, WAF, or enhanced cluster.

The node shape and count are intentionally not configurable. If Ampere Always
Free capacity is unavailable, the apply must fail rather than create a paid
shape. Before every apply, verify Limits, Quotas and Usage in the target region
and inspect the Terraform plan for unexpected resources.

## State and execution

The production state belongs in an OCI Resource Manager stack, not in GitHub or
on a laptop. Resource Manager provides state storage, locking and drift history
and is part of OCI Always Free. Configure the stack from the
`bhukum1/bhuplabs-kubernetes` GitHub repository with this directory as its
working directory and Terraform 1.5.x.

Local Terraform is for formatting and preflight validation. A local plan
requires an authenticated OCI CLI/provider profile and a private
`terraform.tfvars` copied from the example.

Set `kubernetes_version` to the exact OKE patch version offered in the target
region at plan time. The value must be reviewed again before each control-plane
upgrade; Terraform must not select a version implicitly.

```bash
terraform -chdir=terraform/oke init
terraform -chdir=terraform/oke fmt -check
terraform -chdir=terraform/oke validate
terraform -chdir=terraform/oke plan
```

Never commit Terraform state, a kubeconfig, OCI API keys, private SSH keys, or
Resource Manager variables containing credentials.

## Private API operations

Day-to-day deployment will use Flux from inside OKE. Administrative `kubectl`
access must enter through OCI Cloud Shell private networking or an explicitly
approved short-lived access path. Do not make the OKE API public merely to make
GitHub Actions deployment convenient.

## Post-provision gates

Do not direct production DNS at the new load balancer until all gates pass:

1. Both nodes are Ready and use the declared A1 shape.
2. Calico policy enforcement, Flux, ingress, cert-manager and external-dns are
   healthy.
3. PostgreSQL restore/clean bootstrap and off-host backup restore are proven.
4. Application smoke tests and public blackbox probes pass.
5. The OCI cost report shows no unexpected chargeable resource.
