# Login with AppRole
path "auth/approle/login" {
  capabilities = [ "create", "read" ]
}

# Access path to generate DB credentials
path "database/creds/appro" {
  capabilities = [ "read"  ]
}

# needed if you want to allow the app to also revoke lease
path "sys/revoke/database/creds/appro/*" {
  capabilities = [ "update" ]
}


