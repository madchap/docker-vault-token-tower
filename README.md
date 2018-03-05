# docker-vault-token-tower
Helper container acting as trusted party to make approle stuff work.

# Status
Don't look at it.

This is just a POC container. Do not run this in production, it is a quick and dirty thing.
Instead, you'd likely have your configuration management tool act as the trust entity this container simulates.

# Overview

Based on what is described in Hashicorp's Vault [approle advanced features](https://www.vaultproject.io/guides/identity/authentication.html), this container will act at the trusted entity to:
* get role ID and deliver it to the "app"
* get wrapped secret ID and deliver the wrapped token to the "app".

The app will run on port 5000.

From the page above, and just in case it dissapears, the nice schema is this one.


![approle_flow](assets/vault-approle-workflow2-e748e541.png)


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
The token value is expected to be found at the root of the container, in a file called `token`.


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