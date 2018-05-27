#!/usr/bin/env bash
set -e

# base of this script taken from https://raw.githubusercontent.com/hashicorp/best-practices/master/packer/config/vault/scripts/setup_vault.sh

# docker containers in my case, running on same host
psql_host=psql
consul_host=127.0.0.1
export VAULT_ADDR="http://127.0.0.1:8200"

cget() { curl -sf "http://${consul_host}:8500/v1/kv/service/vault/$1?raw"; }

if [ ! $(cget root-token) ]; then
	echo "Initialize Vault (1 key)"
	vault operator init -key-shares=1 -key-threshold=1 | tee /tmp/vault.init > /dev/null

	echo "Remove control code from output, if necessary"
	sed -i 's/\x1b\[[0-9;]*m//g' /tmp/vault.init

	# Store master keys in consul for operator to retrieve and remove
	COUNTER=1
	cat /tmp/vault.init | grep '^Unseal' | awk '{print $4}' | for key in $(cat -); do
		curl -fXPUT ${consul_host}:8500/v1/kv/service/vault/unseal-key-$COUNTER -d $key
		echo -n "$key" > ~/.seeds/vault_demo_unseal_key
		COUNTER=$((COUNTER + 1))
	done

	export ROOT_TOKEN=$(cat /tmp/vault.init | grep '^Initial' | awk '{print $4}')
	curl -fXPUT ${consul_host}:8500/v1/kv/service/vault/root-token -d $ROOT_TOKEN
	echo -n "$ROOT_TOKEN" > ~/.seeds/vault_demo_root_token

	echo "Remove master keys from disk"
	shred /tmp/vault.init

	echo "Setup Vault demo"

else
	echo
	echo "Vault has already been initialized, skipping."
	echo
	echo "Hint: You can delete all data in consul to be able to re-init with:"
	echo "curl -X DELETE 'http://${consul_host}:8500/v1/kv/?recurse'"
	echo
	echo "Dump the data to double check if you want with:"
	echo "curl ${consul_host}:8500/v1/kv/?recurse | jq"
fi

echo "Unsealing Vault"
vault operator unseal $(cget unseal-key-1)
#vault unseal $(cget unseal-key-2)
#vault unseal $(cget unseal-key-3)

echo "Authenticating"
export VAULT_TOKEN=$(curl -sXGET ${consul_host}:8500/v1/kv/service/vault/root-token |jq -r .[].Value |base64 -d)

echo "Token is $VAULT_TOKEN"

echo "Mounting approle backend"
vault auth enable approle

echo "Mounting database backend"
vault secrets enable database

echo "Configuring database backend"
vault write database/config/vault_sandbox plugin_name=postgresql-database-plugin allowed_roles="admin,appro" connection_url="postgresql://vault:Vault@${psql_host}:5432/vault_sandbox?sslmode=disable"

echo "Configuring database roles"
vault write database/roles/admin \
  db_name=vault_sandbox \
  creation_statements="CREATE ROLE \"{{name}}\" WITH SUPERUSER LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';" \
  revocation_sql="SELECT revoke_access('{{name}}'); DROP user \"{{name}}\";" \
  default_ttl="2h" \
  max_ttl="12h"

vault write database/roles/appro \
  db_name=vault_sandbox \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  revocation_sql="SELECT revoke_access('{{name}}'); DROP user \"{{name}}\";"  \
  default_ttl="1h" \
  max_ttl="24h"


echo "Setting up AppRole for witness app"
vault policy write witness-app ../policies/witnessapp.hcl

echo "Initializing AppRole backend policies"
vault policy write vault-tower ../policies/vault-token-tower-approle.hcl

echo
echo "Vault setup complete."

instructions() {
	cat <<EOF

Vault has been automatically initialized and unsealed once. Future unsealing must
be done manually.

The unseal keys and root token have been temporarily stored in Consul K/V.

  /service/vault/root-token
  /service/vault/unseal-key-{1..5}

Please securely distribute and record these secrets and remove them from Consul.
EOF
}

instructions

exit 0
