# Create and manage roles
path "auth/approle/*" {
  capabilities = [ "read", "list", "create", "update", "delete", "sudo" ]
}
