# Node02 OKE access

These commands provide short-lived administrative access from node02 to the
private OKE API through OCI Bastion. The installer places the public resource
identifiers in `/etc/localshops/oke-access.env`; OCI credentials remain in the
operator's standard OCI CLI profile and are never stored in this repository.

```bash
oke-connect
kubectl get pods -A
oke-status
oke-disconnect
```

`oke-connect` creates a dedicated SSH key on first use, requests a three-hour
port-forwarding session, generates `~/.kube/config`, and binds the tunnel only
to node02 loopback. The cluster API remains private and the Bastion accepts SSH
connections only from node02's fixed public `/32`.
