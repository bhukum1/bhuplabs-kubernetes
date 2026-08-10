# Permit browsing KV v2 folders and metadata in the Vault UI.
path "secret/metadata" {
  capabilities = ["list"]
}

path "secret/metadata/*" {
  capabilities = ["read", "list"]
}

# Permit reading secret values, but not creating, updating, deleting,
# undeleting, destroying, or changing metadata.
path "secret/data/*" {
  capabilities = ["read"]
}
