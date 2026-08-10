# Bhuplabs SSO

Keycloak is published at `https://auth.bhuplabs.dev`. This small installation
uses only Keycloak's required `master` realm for administration and application
SSO. Self-registration is disabled. Administrators create users and assign
groups.

## Initial access

- Realm: `master`
- Username: `admin`
- Email: `admin@bhuplabs.dev`

The administrator password is stored outside Git in macOS Keychain:

```bash
security find-generic-password \
  -s bhuplabs-keycloak-bootstrap \
  -a admin \
  -w
```

This account administers Keycloak and authenticates to the configured
applications. Using a dedicated application realm is recommended if more
users or stronger privilege separation are needed later.

## Groups

- `platform-admins`: platform administrators
- `platform-users`: users allowed to access platform applications
- `grafana-viewers`: Grafana Viewer mapping

Vault's Keycloak role intentionally grants only Vault's `default` policy.
Membership in `platform-admins` does not automatically grant unrestricted
Vault access. Add narrowly scoped Vault policies and identity-group aliases
only when required.

## OIDC clients

| Client | Redirect URI |
| --- | --- |
| `grafana` | `https://grafana.bhuplabs.dev/login/generic_oauth` |
| `vault` | `https://vault.bhuplabs.dev/ui/vault/auth/oidc/oidc/callback` |
| `n8n-proxy` | `https://n8n.bhuplabs.dev/oauth2/callback` |

Client secrets and the oauth2-proxy cookie key live under
`secret/keycloak/*` in Vault. They are injected into memory-backed pod volumes
and are not Kubernetes Secrets or repository files.

## Operational checks

```bash
kubectl get pods -n keycloak --context=kubernetes-admin@kubernetes
kubectl get certificate -n keycloak --context=kubernetes-admin@kubernetes
curl -sS \
  https://auth.bhuplabs.dev/realms/master/.well-known/openid-configuration |
  jq -r .issuer
curl -I https://n8n.bhuplabs.dev/
```

The exact chatbot production webhook remains outside SSO:

```bash
curl -H 'Content-Type: application/json' \
  --data '{"action":"sendMessage","sessionId":"curl-test","chatInput":"hi"}' \
  https://n8n.bhuplabs.dev/webhook/chatbot
```

If it returns `The requested webhook ... is not registered`, activate the
workflow in n8n. That response confirms routing reached n8n and is unrelated
to Keycloak.
