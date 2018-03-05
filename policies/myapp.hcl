# Login with AppRole
path "auth/approle/login" {
  capabilities = [ "create", "read" ]
}
