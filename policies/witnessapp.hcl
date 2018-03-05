# Login with AppRole
path "auth/approle/login" {
  capabilities = [ "create", "read" ]
}

# Access path to generate DB credentials
path "database/creds/appro" {
  capabilities = [ "read" ]
}
