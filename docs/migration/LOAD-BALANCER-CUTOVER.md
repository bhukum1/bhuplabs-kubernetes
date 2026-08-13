# LocalShops OKE load-balancer cutover

This runbook records the production traffic state established on 13 August
2026. The existing OCI Flexible Load Balancer is preserved outside the OKE
Terraform stack so that it remains within the 10-Mbps Always Free boundary.

## Active traffic path

- Public IP: `140.245.252.229`
- HTTP listener `n8n-http` (`TCP/80`) -> `localshops-oke-http`
- HTTPS listener `n8n` (`TCP/443`) -> `localshops-oke-https`
- OKE HTTP backends: `10.0.30.23:30080`, `10.0.30.26:30080`
- OKE HTTPS backends: `10.0.30.23:30443`, `10.0.30.26:30443`
- Both backend sets use TCP health checks on their respective NodePorts.

Traefik terminates TLS in OKE. cert-manager maintains the
`localshops/localshops-tls` secret with an HTTP-01 certificate for
`shops.bhuplabs.dev`, `app.bhuplabs.dev`, and `api.bhuplabs.dev`.

The Traefik HTTP redirect uses public port `443` and priority `100`. This is
higher than the normal application catch-all routes but lower than the longer
exact cert-manager HTTP-01 routes, allowing unattended renewal.

## Rollback state

Do not delete these preserved backend sets until the OKE environment has passed
the agreed observation period:

- Old HTTP backend set: `n8n-http`
- Old HTTPS backend set: `n8n`

Rollback requires changing only the listeners' default backend-set pointers:

```bash
oci lb listener update \
  --load-balancer-id <load-balancer-ocid> \
  --listener-name n8n-http \
  --default-backend-set-name n8n-http \
  --port 80 --protocol TCP \
  --connection-configuration-idle-timeout 300 \
  --force --wait-for-state SUCCEEDED

oci lb listener update \
  --load-balancer-id <load-balancer-ocid> \
  --listener-name n8n \
  --default-backend-set-name n8n \
  --port 443 --protocol TCP \
  --connection-configuration-idle-timeout 300 \
  --force --wait-for-state SUCCEEDED
```

## Verification

After any listener or worker-node change, require both backend sets to report
`OK`, then verify:

```bash
curl --fail https://shops.bhuplabs.dev/api/health
curl --fail https://app.bhuplabs.dev/api/health
curl --fail https://api.bhuplabs.dev/health/ready
curl --head http://shops.bhuplabs.dev/
```

OKE node private IPs are not durable identities. When a node pool replaces a
worker, update the corresponding load-balancer backends and confirm health
before draining or removing the previous backend.
