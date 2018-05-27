storage "consul" {
  address = "consul1:8500"
  path = "vault"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = true // dev only
}

ui = true
