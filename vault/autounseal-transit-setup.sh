#!/usr/bin/env bash

# Start the Vault0 server
# 
# export VAULT_ADDR=http://127.0.0.100:8200
# export VAULT_IP=127.0.0.100
# export VAULT_PORT=8200
# export VAULT_API_ADDR=http://127.0.0.100:8200
# export VAULT_CACERT=
# export VAULT_CLIENT_CERT=
# export VAULT_CLIENT_KEY=
# export VAULT_USER=$(whoami)
# export VAULT_ZERO_HOME=~/chef/vault0
# export VAULT_CONFIG_PATH=~/.config/vault/vault0.json
# export VAULT_TOKEN="$(secret-tool lookup vault zero policy root|head)"
# sudo --preserve-env ./vault0.sh stop vault0
# sudo --preserve-env ./vault0.sh clean vault0
# sudo --preserve-env ./vault0.sh setup vault0
# sudo --preserve-env ./vault0.sh status vault0
# sudo --preserve-env ./vault0.sh backup vault0
# 
# Set the environment variables: VAULT_ADDR and VAULT_TOKEN
export VAULT_ADDR=http://127.0.0.100:8200
export VAULT_TOKEN="$(secret-tool lookup vault zero policy root|head)"

vault status

# Enable audit log
vault audit enable file file_path=audit.log

# Enable and configure transit secrets engine
vault secrets enable transit
vault write -f transit/keys/autounseal

# Create an autounseal policy
vault policy write autounseal -<<EOF
path "transit/encrypt/autounseal" {
   capabilities = [ "update" ]
}

path "transit/decrypt/autounseal" {
   capabilities = [ "update" ]
}
EOF

# Create a token for Vault 1 to use for root key encryption
vault token create -orphan -policy="autounseal" -wrap-ttl=120 -period=24h -field=wrapping_token > wrapping-token.txt

