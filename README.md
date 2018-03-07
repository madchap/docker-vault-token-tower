# docker-vault-token-tower
Helper container acting as trusted party to make approle stuff work.

You can `docker pull madchap/docker-vault-token-tower`.

# Status
Don't look at it.

This is just a POC container and a simple 'witness' python app. Do not run this container in production, it is a quick and dirty thing.
Instead, you'd likely have your configuration management tool act as the trust entity this container simulates.

# Assumptions
* docker hosts for vault and postgres container, sharing network called "vault_net"
* The witness app will run on the docker host.
* `vault` and `psql` are the respective names of the containers.
* Secret backends are mounted at their default locations.
* `approle` auth backend is enabled.
* `database` secrets backend is enabled.

# Pre-requisite containers to run Vault
## Vault (and consul) container
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

`$ docker run -d --network vault_net --restart=unless-stopped --name=vault --cap-add=IPC_LOCK -v vault_config:/vault/config -v vault_logs:/vault/logs -v vault_file:/vault/file vault server`

**Consul**

Get some persistence for (nearly) free.

`$ docker run -d --network vault_net --restart=unless-stopped --name consul1 -p 8500:8500 -p 8600:8600/udp -v consul_data_1:/consul/data -v consul_config_1:/consul/config consul agent -server -ui -client 0.0.0.0 -node consul1 -bootstrap`

# Overview of the small REST API server, vault-tower

Based on what is described in Hashicorp's Vault [approle advanced features](https://www.vaultproject.io/guides/identity/authentication.html), this container will act at the trusted entity to:
* get role ID and deliver it to the "app"
* get wrapped secret ID and deliver the wrapped token to the "app".

The app will run on port 5000.

From the page above, and just in case it dissapears, the nice schema is this one.


![approle_flow](assets/vault-approle-workflow2-e748e541.png)


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

Create the policy, and issue a token against it. It will be used by the vault-tower container app. For example:

```
$ vault policy write vault-tower vault-token-tower-approle.hcl
```

```
$ vault token create --display-name=vault-tower -policy=vault-tower
```

## vault-token-tower token
The token value is expected to be found at the root of the container, in a file called `token`. You will get this file as an admin and put it there manually.
It is your trusted container, it's gotta start somewhere (I guess).

# REST Endpoints
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
$ curl -s localhost:5000/token |jq            
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
Skipping over the details, `createdb vault_sandbox`.


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

Insert some data:

```
insert into public.kv values (nextval('kv_id_seq'), 'poc', 'yes');
insert into public.kv values (nextval('kv_id_seq'), 'Vault', 'rules');
```

## Vault 
* Mount secrets backend

`vault mount database`

* Configure database. Roles are mapped here already, in our case `admin` (not used in this POC), and `appro`, which is the role that the witness app will use.

`vault write database/config/vault_sandbox plugin_name=postgresql-database-plugin allowed_roles="admin,appro" connection_url="postgresql://vault:Vault@psql:5432/vault_sandbox?sslmode=disable"`

### Vault roles
* Configure vault roles, that will give specific grants and revoke based on what you want.

```
$ vault write database/roles/admin \
  db_name=vault_sandbox \
  creation_statements="CREATE ROLE \"{{name}}\" WITH SUPERUSER LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';" \
  revocation_sql="SELECT revoke_access('{{name}}'); DROP user \"{{name}}\";" \
  default_ttl="2h" \
  max_ttl="12h"
```

The `approle` can only read the data. We will use that one actually.

```
$ vault write database/roles/appro \
  db_name=vault_sandbox \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  revocation_sql="SELECT revoke_access('{{name}}'); DROP user \"{{name}}\";"  \
  default_ttl="1h" \
  max_ttl="24h"
```

* List roles

` vault list database/roles`

* Get your creds through the named endpoint to test it, example:

`vault read database/creds/appro`

# The Witness app
The witness app is here to show us that stuff actually works.

## Policy
Its Vault witness policy will be more restricted:

```
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
```

Create the policy and the witness role:

```
$ vault policy write witness-app witnessapp.hcl
```

```
$ vault write auth/approle/role/witness-role policies="witness-app"
```

Launch it manually, after having launched the "token-tower" container -- our trusted entity.

A successful run output would look something like this:

```
/usr/bin/python3.6 /home/fblaise/gitrepos/docker-vault-token-tower/witnessapp/witness.py

Welcome to the witness app.
I will use my companion vault-tower at http://localhost:5000, Vault at http://localhost:8200 and use role witness-role.

Role id: 06ffa86f-41d1-7090-80b9-e34d6c09eeb1
Wrapped token: e1375601-2b07-3752-49a0-5ff58197b562
Secret id: 2f45d7f6-6df9-2ffc-c283-384c334eccc4
Token: 72510315-e176-8585-92cb-7014e542b6ee
Postgres dynamic creds: {'request_id': 'd627d669-9f3d-1b6d-a6a7-7b72518cfd65', 'lease_id': 'database/creds/appro/1f8af781-ad5d-1616-e97a-cf08e4d8802f', 'renewable': True, 'lease_duration': 3600, 'data': {'password': 'A1a-vp6t415v1up7utvq', 'username': 'v-approle-appro-pqxr5t11s72164vy7r77-1520380950'}, 'wrap_info': None, 'warnings': None, 'auth': None}

Rows returned:
  1 k1 v1
  2 winner yes
  3 meetup DevSecOps Lausanne
  4 thanks to all

I am done! I can now delete my non-needed postgreSQL credentials.

My lease id is database/creds/appro/1f8af781-ad5d-1616-e97a-cf08e4d8802f, and that's all I need.

Process finished with exit code 0
```