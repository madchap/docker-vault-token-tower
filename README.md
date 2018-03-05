# docker-vault-token-tower
Helper container acting as trusted party to make approle stuff work.

# Status
Don't look at it.

This is just a POC container and a simple 'witness' python app. Do not run this container in production, it is a quick and dirty thing.
Instead, you'd likely have your configuration management tool act as the trust entity this container simulates.

# Assumptions
* docker hosts for vault and postgres container, sharing network called "vault_net"
* `vault` and `psql` are the respective names of the containers.
* Secret backends are mounted at their default locations.
* `approle` auth backend is enabled.

# Overview

Based on what is described in Hashicorp's Vault [approle advanced features](https://www.vaultproject.io/guides/identity/authentication.html), this container will act at the trusted entity to:
* get role ID and deliver it to the "app"
* get wrapped secret ID and deliver the wrapped token to the "app".

The app will run on port 5000.

From the page above, and just in case it dissapears, the nice schema is this one.


![approle_flow](assets/vault-approle-workflow2-e748e541.png)


# Vault (and consul)container
Create the necessary docker volumes.

**Vault**

I have the following server config file, living in the `vault_config` docker volume:

```
storage "consul" {
  address = "consul1:8500"
  path = "vault"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = true // dev only
}
```

`docker run -d --network vault_net --restart=unless-stopped --name=vault --cap-add=IPC_LOCK -v vault_config:/vault/config -v vault_logs:/vault/logs -v vault_file:/vault/file vault server`

**Consul**

`docker run -d --network vault_net --restart=unless-stopped --name consul1 -p 8500:8500 -p 8600:8600/udp -v consul_data_1:/consul/data -v consul_config_1:/consul/config consul agent -server -ui -client 0.0.0.0 -node consul1 -bootstrap`

# This container -- vault-token-tower

The container will use its own Vault token, with a policy capable of dealing with the approle auth backend, such as the one below.

```
# Mount the AppRole auth backend
path "sys/auth/approle" {
  capabilities = [ "create", "read", "update", "delete", "sudo" ]
}

# Configure the AppRole auth backend
path "sys/auth/approle/*" {
  capabilities = [ "create", "read", "update", "delete" ]
}

# Create and manage roles
path "auth/approle/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}

# Write ACL policies
path "sys/policy/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}
```

Create the policy, and issue a token against it. It will be used by the vault-tower container app.

## vault-token-tower token
The token value is expected to be found at the root of the container, in a file called `token`. You will get this file as an admin and put it there manually.
It is your trusted container, it's gotta start somewhere (I guess).

# Endpoints
## roleid
Get the role id, such as:

```
$ curl -s -XGET localhost:5000/roleid/meetup-demo-role |jq                                                                 
{
  "role_id": "b0c679a2-a44b-a28e-57de-35a1714d60b0"
}
```

## wraptoken
Get the wrap token id, such as:
```
$  curl -s localhost:5000/wraptoken/meetup-demo-role -XPOST |jq
{
  "wrap_token": "a9304e63-6cd8-db67-b6cf-b74c618b81ad"
}
```

## token
Basically an endpoint to lookup the token in use by the container.
```
curl -s localhost:5000/token |jq            
{
  "token": {
    "auth": null,
    "data": {
      [...]
      "path": "auth/token/create",
      "policies": [
        "default",
        "vault-tower"
      ],
      "renewable": true,
      "ttl": 2760127
    },
    [...]
  }
}
```

# Example use-case with postgreSQL

The goal of this use-case is to have a random script read out data from a postgres database `vault_sandbox` and table `kv`.

## postgres docker
`docker volume create --name=pgdata`

`docker run --network=vault_net -p 5432:5432 --name psql -e POSTGRES_PASSWORD=yourpass -v pgdata:/var/lib/postgresql/data -d postgres:9.5
`

## Database
Skipping over the details, `createdb vault_sandbox`


## Table
Create a table `kv`, arbitrarily with this schema:

```
CREATE TABLE public.kv
(
    id integer NOT NULL DEFAULT nextval('kv_id_seq'::regclass),
    key text COLLATE pg_catalog."default",
    value text COLLATE pg_catalog."default",
    CONSTRAINT kv_pkey PRIMARY KEY (id)
)
WITH (
    OIDS = FALSE
);
```
## Vault 
* Mount secrets backend

`vault mount database`

* Configure database. Roles are mapped here already.

`vault write database/config/vault_sandbox plugin_name=postgresql-database-plugin allowed_roles="admin,appro" connection_url="postgresql://vault:Vault@psql:5432/vault_sandbox?sslmode=disable"`

### Vault roles
* Configure vault roles, that will give specific grants and revoke based on what you want.

```
vault write database/roles/admin \
  db_name=vault_sandbox \
  creation_statements="CREATE ROLE \"{{name}}\" WITH SUPERUSER LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';" \
  revocation_sql="SELECT revoke_access('{{name}}'); DROP user \"{{name}}\";" \
  default_ttl="2h" \
  max_ttl="12h"
```

The `approle` can only read the data. We will use that one actually.

```
vault write database/roles/appro \
  db_name=vault_sandbox \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON   ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  revocation_sql="SELECT revoke_access('{{name}}'); DROP user \"{{name}}\";"  \
  default_ttl="1h" \
  max_ttl="24h"
```

* List roles

` vault list database/roles`

* Get your creds through the named endpoint, example:

`vault read database/creds/appro`

# The Witness app
The witness app is here to show us that stuff actually works.

Launch it manually, after having launched the "token-tower" container -- our trusted entity.
