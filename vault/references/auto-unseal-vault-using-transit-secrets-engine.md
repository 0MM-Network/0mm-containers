# [Auto unseal](https://developer.hashicorp.com/vault/tutorials/auto-unseal)

Tutorial:

*   [Auto-unseal using transit](https://developer.hashicorp.com/vault/tutorials/auto-unseal/autounseal-transit
*   [Auto unseal](https://developer.hashicorp.com/vault/tutorials/auto-unseal)

## Auto-unseal Vault using transit secrets engine

When a Vault server starts, it starts in a [sealed](https://developer.hashicorp.com/vault/docs/concepts/seal) state. It does not know how to decrypt data, and has limited access. Before you can perform an operation, you must unseal it. Unsealing is the process of constructing the master key necessary to decrypt the data encryption key.

## [Challenge](https://developer.hashicorp.com/vault/tutorials/auto-unseal/autounseal-transit#challenge)

Vault unseal operation requires a quorum of existing unseal keys split by Shamir's Secret sharing algorithm. This prevents one person from having full control of Vault. However, this process is manual and can become painful when you have several Vault clusters as there are now different key holders with different keys.

However, this process is manual and can become painful when you have several Vault clusters as there are now different key holders with different keys.

## [Solution](https://developer.hashicorp.com/vault/tutorials/auto-unseal/autounseal-transit#solution)

Vault supports opt-in automatic unsealing via [transit secrets engine](https://developer.hashicorp.com/vault/docs/secrets/transit). This feature enables operators to delegate the unsealing process to a trusted Vault environment to ease operations.

This tutorial demonstrates how to auto-unseal a Vault with the transit secrets engine.

## [Prerequisites](https://developer.hashicorp.com/vault/tutorials/auto-unseal/autounseal-transit#prerequisites)

To perform the tasks described in this tutorial, you need Vault installed.

## [Scenario introduction](https://developer.hashicorp.com/vault/tutorials/auto-unseal/autounseal-transit#scenario-introduction)

For the purpose of demonstration, you are going to run two instances of Vault as described in the following diagram:

In reality, the **Vault 1** and **Vault 2** are two separate stand-alone Vault clusters where one protects the other's root key. Nonetheless, the steps described in this tutorial directly applies to your clustered environment. The main difference would be the location (address) of **Vault 1** and **Vault 2**.

In this scenario, **Vault 1** (`$VAULT_ADDR`) is the encryption service provider, and its transit key protects the **Vault 2** server's master key.

![Scenario Overview](Auto-unseal%20Vault%20using%20transit%20secrets%20engine%20_%20Vault%20_%20HashiCorp%20Developer_files/assets_006.avif)

## [](https://developer.hashicorp.com/vault/tutorials/auto-unseal/autounseal-transit#step-1-configure-auto-unseal-key-provider-vault-1)Step 1: Configure auto-unseal key provider (Vault 1)

Bash script to setup Vault 1

If you prefer running a script instead of manually setting up the Vault 1 server, follow these steps.

1.  Create a setup script named `autounseal-transit-setup.sh`.
    
    autounseal-transit-setup.sh
    
    \# Start the Vault 1 server in dev mode
    \# The system output will be stored in the vault-1.log file
    vault server -dev -dev-root-token-id root > vault-1.log 2>&1 &
    
    sleep 1
    
    \# Set the environment variables: VAULT\_ADDR and VAULT\_TOKEN
    export VAULT\_ADDR\=http://127.0.0.1:8200
    export VAULT\_TOKEN\=root
    
    \# Enable audit log
    vault audit enable file file\_path=audit.log
    
    \# Enable and configure transit secrets engine
    vault secrets enable transit
    vault write -f transit/keys/autounseal
    
    \# Create an autounseal policy
    vault policy write autounseal -<<EOF
    path "transit/encrypt/autounseal" {
       capabilities = \[ "update" \]
    }
    
    path "transit/decrypt/autounseal" {
       capabilities = \[ "update" \]
    }
    EOF
    
    \# Create a token for Vault 2 to use for root key encryption
    vault token create -orphan -policy="autounseal" -wrap-ttl=120 -period=24h -field=wrapping\_token > wrapping-token.txt
    
    ```
    # Start the Vault 1 server in dev mode
    # The system output will be stored in the vault-1.log file
    vault server -dev -dev-root-token-id root > vault-1.log 2>&1 &
    
    sleep 1
    
    # Set the environment variables: VAULT_ADDR and VAULT_TOKEN
    export VAULT_ADDR=http://127.0.0.1:8200
    export VAULT_TOKEN=root
    
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
    
    # Create a token for Vault 2 to use for root key encryption
    vault token create -orphan -policy="autounseal" -wrap-ttl=120 -period=24h -field=wrapping_token > wrapping-token.txt
    ```
    
2.  Make the file executable.
    
    $ chmod +x autounseal-transit-setup.sh
    
    ```
    $ chmod +x autounseal-transit-setup.sh
    ```
    
3.  Run the script.
    
    $ ./autounseal-transit-setup.sh
    
    ```
    $ ./autounseal-transit-setup.sh
    ```
    
    **Output:**
    
    Success! Enabled the file audit device at: file/
    Success! Enabled the transit secrets engine at: transit/
    Key                       Value
    \---                       -----
    allow\_plaintext\_backup    false
    auto\_rotate\_period        0s
    deletion\_allowed          false
    derived                   false
    exportable                false
    imported\_key              false
    keys                      map\[1:1693608276\]
    latest\_version            1
    min\_available\_version     0
    min\_decryption\_version    1
    min\_encryption\_version    0
    name                      autounseal
    supports\_decryption       true
    supports\_derivation       true
    supports\_encryption       true
    supports\_signing          false
    type                      aes256-gcm96
    Success! Uploaded policy: autounseal
    
    ```
    Success! Enabled the file audit device at: file/
    Success! Enabled the transit secrets engine at: transit/
    Key                       Value
    ---                       -----
    allow_plaintext_backup    false
    auto_rotate_period        0s
    deletion_allowed          false
    derived                   false
    exportable                false
    imported_key              false
    keys                      map[1:1693608276]
    latest_version            1
    min_available_version     0
    min_decryption_version    1
    min_encryption_version    0
    name                      autounseal
    supports_decryption       true
    supports_derivation       true
    supports_encryption       true
    supports_signing          false
    type                      aes256-gcm96
    Success! Uploaded policy: autounseal
    ```
    

Now, you can skip to [Step 2: Configure auto-unseal (Vault 2)](https://developer.hashicorp.com/vault/tutorials/auto-unseal/autounseal-transit#step-2-configure-auto-unseal-vault-2) section.

### [](https://developer.hashicorp.com/vault/tutorials/auto-unseal/autounseal-transit#start-vault-1-server)Start Vault 1 server

1.  Start a Vault dev server with `root` as the root token. Output the system log in a file named `vault-1.log`.
    
    $ vault server -dev -dev-root-token-id root \> vault-1.log 2>&1 &
    
    ```
    $ vault server -dev -dev-root-token-id root > vault-1.log 2>&1 &
    ```
    
    The Vault dev server defaults to running at `127.0.0.1:8200`. The server is also initialized and unsealed.
    
    Insecure operation
    
    Do not run a Vault dev server in production. This approach simplifies the unsealing process for this tutorial.
    
2.  Export an environment variable for the `vault` CLI to address the Vault server.
    
    $ export VAULT\_ADDR\=http://127.0.0.1:8200
    
    ```
    $ export VAULT_ADDR=http://127.0.0.1:8200
    ```
    
3.  Export an environment variable for the `vault` CLI to authenticate with the Vault server.
    
    $ export VAULT\_TOKEN\=root
    
    ```
    $ export VAULT_TOKEN=root
    ```
    

### [](https://developer.hashicorp.com/vault/tutorials/auto-unseal/autounseal-transit#setup-the-transit-secrets-engine)Setup the transit secrets engine

The first step is to enable and configure the `transit` secrets engine on **Vault 1**.

CLI commandAPI call using cURLWeb UI

1.  Enable an audit device. You will examine the audit log later in the tutorial.
    
    $ vault audit enable file file\_path=audit.log
    
    ```
    $ vault audit enable file file_path=audit.log
    ```
    
2.  Execute the following command to enable the `transit` secrets engine.
    
    $ vault secrets enable transit
    
    ```
    $ vault secrets enable transit
    ```
    
3.  Execute the following command to create an encryption key named, `autounseal`.
    
    $ vault write -f transit/keys/autounseal
    
    ```
    $ vault write -f transit/keys/autounseal
    ```
    
    Note
    
    To learn more about the `transit` secrets engine, refer to the [Encryption as a Service: Transit Secrets Engine](https://developer.hashicorp.com/vault/tutorials/encryption-as-a-service/eaas-transit).
    
4.  Create a policy named `autounseal` which permits `update` against `transit/encrypt/autounseal` and `transit/decrypt/autounseal` paths.
    
    $ vault policy write autounseal -<<EOF
    path "transit/encrypt/autounseal" {
       capabilities = \[ "update" \]
    }
    
    path "transit/decrypt/autounseal" {
       capabilities = \[ "update" \]
    }
    EOF
    
    ```
    $ vault policy write autounseal -<<EOF
    path "transit/encrypt/autounseal" {
       capabilities = [ "update" ]
    }
    
    path "transit/decrypt/autounseal" {
       capabilities = [ "update" ]
    }
    EOF
    ```
    
    **Output:**
    
    Success! Uploaded policy: autounseal
    
    ```
    Success! Uploaded policy: autounseal
    ```
    
5.  Create an orphan [periodic](https://developer.hashicorp.com/vault/docs/commands/token/create#period) client token with the `autounseal` policy attached and [response wrap](https://developer.hashicorp.com/vault/docs/concepts/response-wrapping) it with TTL of 120 seconds. Store the generated wrapping token value in a file, `wrapping-token.txt`.
    
    $ vault token create -orphan -policy="autounseal" \\
       -wrap-ttl=120 -period=24h \\
       -field=wrapping\_token > wrapping-token.txt
    
    ```
    $ vault token create -orphan -policy="autounseal" \
       -wrap-ttl=120 -period=24h \
       -field=wrapping_token > wrapping-token.txt
    ```
    
    Note
    
    You can renew periodic tokens within the `period`. By default the transit `autounseal` token renews automatically. An `orphan` token does not have a parent token and is not revoked when the token that created it expires. Learn more about [token hierarchies.](https://developer.hashicorp.com/vault/docs/concepts/tokens#token-hierarchies-and-orphan-tokens)
    
    The generated token is what you pass to **Vault 2** to decrypt its root key and unseal Vault.
    
    $ cat wrapping-token.txt
    
    ```
    $ cat wrapping-token.txt
    ```
    
    **Example output:**
    
    hvs.CAESIJvhwiAb8-Xx3mc23ju8W4Kcp8JBXs6LOwJQ3ILxcaWGGh4KHGh2cy4zVHRKekRWdldyNERtbm11ZE9DTldWa0s
    
    ```
    hvs.CAESIJvhwiAb8-Xx3mc23ju8W4Kcp8JBXs6LOwJQ3ILxcaWGGh4KHGh2cy4zVHRKekRWdldyNERtbm11ZE9DTldWa0s
    ```
    

1.  Enable an audit device. You will examine the audit log later in the tutorial.
    
    $ curl --header "X-Vault-Token: $VAULT\_TOKEN" \\
       --request PUT \\
       --data '{"type":"file", "options":{"file\_path":"audit.log"}}' \\
       $VAULT\_ADDR/v1/sys/audit/file
    
    ```
    $ curl --header "X-Vault-Token: $VAULT_TOKEN" \
       --request PUT \
       --data '{"type":"file", "options":{"file_path":"audit.log"}}' \
       $VAULT_ADDR/v1/sys/audit/file
    ```
    
    Be sure to pass your valid token in the `X-Vault-Token` header.
    
2.  Enable `transit` secrets engine and create a key named, `autounseal`.
    
    $ curl --header "X-Vault-Token: $VAULT\_TOKEN" \\
       --request POST \\
       --data '{"type":"transit"}' \\
       $VAULT\_ADDR/v1/sys/mounts/transit
    
    ```
    $ curl --header "X-Vault-Token: $VAULT_TOKEN" \
       --request POST \
       --data '{"type":"transit"}' \
       $VAULT_ADDR/v1/sys/mounts/transit
    ```
    
3.  Create an encryption key named, `autounseal`.
    
    $ curl --header "X-Vault-Token: $VAULT\_TOKEN" \\
       --request POST \\
       $VAULT\_ADDR/v1/transit/keys/autounseal
    
    ```
    $ curl --header "X-Vault-Token: $VAULT_TOKEN" \
       --request POST \
       $VAULT_ADDR/v1/transit/keys/autounseal
    ```
    
    Tip
    
    To learn more about the `transit` secrets engine, refer to the [Encryption as a Service: Transit Secrets Engine](https://developer.hashicorp.com/vault/tutorials/encryption-as-a-service/eaas-transit).
    
4.  Create the API request payload containing the `autounseal` policy definition which permits `update` against `transit/encrypt/autounseal` and `transit/decrypt/autounseal` paths.
    
    $ tee payload-policy.json <<EOF
    {
      "policy": "path \\"transit/encrypt/autounseal\\" {\\n   capabilities = \[ \\"update\\" \]\\n}\\n\\npath \\"transit/decrypt/autounseal\\" {\\n   capabilities = \[ \\"update\\" \]\\n}\\n"
    }
    EOF
    
    ```
    $ tee payload-policy.json <<EOF
    {
      "policy": "path \"transit/encrypt/autounseal\" {\n   capabilities = [ \"update\" ]\n}\n\npath \"transit/decrypt/autounseal\" {\n   capabilities = [ \"update\" ]\n}\n"
    }
    EOF
    ```
    
5.  Create a policy named `autounseal`.
    
    $ curl --header "X-Vault-Token: $VAULT\_TOKEN" --request PUT \\
       --data @payload-policy.json \\
       $VAULT\_ADDR/v1/sys/policies/acl/autounseal
    
    ```
    $ curl --header "X-Vault-Token: $VAULT_TOKEN" --request PUT \
       --data @payload-policy.json \
       $VAULT_ADDR/v1/sys/policies/acl/autounseal
    ```
    
    Create a policy to permit `update` against `transit/encrypt/<key_name>` and `transit/decrypt/<key_name>` where the `<key_name>` is the name of the encryption key you created in the previous step.
    
6.  Create an orphan [periodic](https://developer.hashicorp.com/vault/api-docs/auth/token#period) client token with the `autounseal` policy attached and [response wrap](https://developer.hashicorp.com/vault/docs/concepts/response-wrapping) it with TTL of 120 seconds. Store the generated wrapping token value in a file, `wrapping-token.txt`.
    
    $ curl --header "X-Vault-Wrap-TTL: 120" \\
       --header "X-Vault-Token: $VAULT\_TOKEN" \\
       --request POST \\
       --data '{"policies":\["autounseal"\], "period":"24h"}' \\
       $VAULT\_ADDR/v1/auth/token/create-orphan \\
       | jq -r ".wrap\_info.token" > wrapped-token.txt
    
    ```
    $ curl --header "X-Vault-Wrap-TTL: 120" \
       --header "X-Vault-Token: $VAULT_TOKEN" \
       --request POST \
       --data '{"policies":["autounseal"], "period":"24h"}' \
       $VAULT_ADDR/v1/auth/token/create-orphan \
       | jq -r ".wrap_info.token" > wrapped-token.txt
    ```
    
    Note
    
    You can renew periodic tokens within the `period`. By default, the transit `autounseal` token renews automatically. An `orphan` token does not have a parent token. Learn more about [token hierarchies.](https://developer.hashicorp.com/vault/docs/concepts/tokens#token-hierarchies-and-orphan-tokens)
    
    The generated token is what you pass to **Vault 2** to decrypt its root key and unseal Vault.
    
    $ cat wrapping-token.txt
    
    ```
    $ cat wrapping-token.txt
    ```
    
    **Example output:**
    
    hvs.CAESIJvhwiAb8-Xx3mc23ju8W4Kcp8JBXs6LOwJQ3ILxcaWGGh4KHGh2cy4zVHRKekRWdldyNERtbm11ZE9DTldWa0s
    
    ```
    hvs.CAESIJvhwiAb8-Xx3mc23ju8W4Kcp8JBXs6LOwJQ3ILxcaWGGh4KHGh2cy4zVHRKekRWdldyNERtbm11ZE9DTldWa0s
    ```
    

Open a web browser and launch the Vault UI (`http://127.0.0.1/ui`) and then log in with token, `root`.

1.  Select **Enable new engine** from the **Secrets engines** page.
    
2.  Select the **Transit** radio button and click **Next**.
    
    ![Select transit secrets engine](Auto-unseal%20Vault%20using%20transit%20secrets%20engine%20_%20Vault%20_%20HashiCorp%20Developer_files/assets_012.avif)
    
3.  Leave the **Path** as `transit`, and click **Enable Engine**.
    
    ![Enable transit secrets engine](Auto-unseal%20Vault%20using%20transit%20secrets%20engine%20_%20Vault%20_%20HashiCorp%20Developer_files/assets_007.avif)
    
4.  Select **Create encryption key** and enter `autounseal` in the **Name** field.
    
5.  Click **Create encryption key** to complete.
    
6.  Select **Policies**, and then select **Create ACL policy**.
    
7.  Enter `autounseal` in the **Name** field, and then enter the following policy in the **Policy** text field.
    
    path "transit/encrypt/autounseal" {
      capabilities \= \[ "update" \]
    }
    
    path "transit/decrypt/autounseal" {
      capabilities \= \[ "update" \]
    }
    
    ```
    path "transit/encrypt/autounseal" {
      capabilities = [ "update" ]
    }
    
    path "transit/decrypt/autounseal" {
      capabilities = [ "update" ]
    }
    ```
    
    Create a policy to allow `update` against `transit/encrypt/<key_name>` and `transit/decrypt/<key_name>` where the `<key_name>` is the name of the encryption key you created in the previous step.
    
8.  Click **Create policy** to complete.
    
9.  Click the Vault CLI shell icon (`>_`) to open a command shell, and run the following command to generate a token.
    
    $ vault write auth/token/create-orphan policies=autounseal -wrap-ttl=120 -field=token
    
    ```
    $ vault write auth/token/create-orphan policies=autounseal -wrap-ttl=120 -field=token
    ```
    
    ![Create a token](Auto-unseal%20Vault%20using%20transit%20secrets%20engine%20_%20Vault%20_%20HashiCorp%20Developer_files/assets_017.avif)
    
10.  Copy the returned value, and store it in a file, `wrapping-token.txt`.
    
    ![Create a token](Auto-unseal%20Vault%20using%20transit%20secrets%20engine%20_%20Vault%20_%20HashiCorp%20Developer_files/assets_016.avif)
    

## [](https://developer.hashicorp.com/vault/tutorials/auto-unseal/autounseal-transit#step-2-configure-auto-unseal-vault-2)Step 2: Configure auto-unseal (Vault 2)

Now, start a second Vault instance which listens to port **8100**. The server configuration file should define a `seal` stanza with parameters properly set based on the tasks you performed in [Step 1](https://developer.hashicorp.com/vault/tutorials/auto-unseal/autounseal-transit#step-1-configure-auto-unseal-key-provider-vault-1).

![Scenario Overview](Auto-unseal%20Vault%20using%20transit%20secrets%20engine%20_%20Vault%20_%20HashiCorp%20Developer_files/assets_003.avif)

1.  Execute the following command to unwrap the secrets passed from **Vault 1** and retrieve the token value.
    
    $ vault unwrap -field=token $(cat wrapping-token.txt)
    
    ```
    $ vault unwrap -field=token $(cat wrapping-token.txt)
    ```
    
    **Example output:**
    
    hvs.CAESIErEuLhua677\_F9Uma0cZ30bpWn1-WafzoQmTGRDxKyaGh4KHGh2cy5VenI2RGw4cHJBVElTUm9MNUYwaUhUNlY
    
    ```
    hvs.CAESIErEuLhua677_F9Uma0cZ30bpWn1-WafzoQmTGRDxKyaGh4KHGh2cy5VenI2RGw4cHJBVElTUm9MNUYwaUhUNlY
    ```
    
2.  Open a terminal where you will run the **Vault 2** server, and set `VAULT_TOKEN` environment variable whose value is the client token you just unwrapped.
    
    **Example:**
    
    $ export VAULT\_TOKEN\="hvs.CAESIErEuLhua677\_F9Uma0cZ30bpWn1-WafzoQmTGRDxKyaGh4KHGh2cy5VenI2RGw4cHJBVElTUm9MNUYwaUhUNlY"
    
    ```
    $ export VAULT_TOKEN="hvs.CAESIErEuLhua677_F9Uma0cZ30bpWn1-WafzoQmTGRDxKyaGh4KHGh2cy5VenI2RGw4cHJBVElTUm9MNUYwaUhUNlY"
    ```
    
3.  Create a server configuration file (`config-autounseal.hcl`) to start a second Vault instance (**Vault 2**).
    
    $ tee config-autounseal.hcl <<EOF
    disable\_mlock = true
    ui=true
    
    storage "raft" {
       path    = "./vault/vault-2"
       node\_id = "vault-2"
    }
    
    listener "tcp" {
      address     = "127.0.0.1:8100"
      tls\_disable = "true"
    }
    
    seal "transit" {
      address = "$VAULT\_ADDR"
      disable\_renewal = "false"
      key\_name = "autounseal"
      mount\_path = "transit/"
      tls\_skip\_verify = "true"
    }
    
    api\_addr = "http://127.0.0.1:8100"
    cluster\_addr = "https://127.0.0.1:8101"
    EOF
    
    ```
    $ tee config-autounseal.hcl <<EOF
    disable_mlock = true
    ui=true
    
    storage "raft" {
       path    = "./vault/vault-2"
       node_id = "vault-2"
    }
    
    listener "tcp" {
      address     = "127.0.0.1:8100"
      tls_disable = "true"
    }
    
    seal "transit" {
      address = "$VAULT_ADDR"
      disable_renewal = "false"
      key_name = "autounseal"
      mount_path = "transit/"
      tls_skip_verify = "true"
    }
    
    api_addr = "http://127.0.0.1:8100"
    cluster_addr = "https://127.0.0.1:8101"
    EOF
    ```
    
    Notice that the `address` points to the Vault server listening to port **8200** (Vault 1). The `key_name` and `mount_path` match to what you created in [Step 1](https://developer.hashicorp.com/vault/tutorials/auto-unseal/autounseal-transit#step-1-configure-auto-unseal-key-provider-vault-1).
    
    Note
    
    The `seal` stanza does not set the `token` value since it's already set as `VAULT_TOKEN` environment variable.
    
    Warning
    
    Although the listener stanza disables TLS (`tls_disable = "true"`) for this tutorial, Vault should always be [used with TLS](https://developer.hashicorp.com/vault/docs/configuration/listener/tcp#tls_cert_file) in production to provide secure communication between clients and the Vault server. It requires a certificate file and key file on each Vault host.
    
4.  Create the raft path directory as configured in the storage stanza.
    
    $ mkdir -p vault/vault-2
    
    ```
    $ mkdir -p vault/vault-2
    ```
    
5.  Start the server using the configuration.
    
    $ vault server -config=config-autounseal.hcl
    
    ```
    $ vault server -config=config-autounseal.hcl
    ```
    
6.  Open another terminal and initialize your second Vault server (**Vault 2**).
    
    $ VAULT\_ADDR=http://127.0.0.1:8100 vault operator init
    
    ```
    $ VAULT_ADDR=http://127.0.0.1:8100 vault operator init
    ```
    
    By passing the `VAULT_ADDR`, the subsequent command gets executed against the second Vault server ([http://127.0.0.1:8100](http://127.0.0.1:8100/)).
    
    **Example output:**
    
    Recovery Key 1: iz1XWxe4CM+wrOGqRCx8ex8kB2XvGJEdfjhXFC+MA6Rc
    Recovery Key 2: rKZETr6IAy686IxfO3ZBKXPDAOkkwkpSepIME+bjeUT7
    Recovery Key 3: 4XA/KJqFOm+jzbBkKQuRVePEYPrQe3H3TmFVmdlUjRFv
    Recovery Key 4: lfnaYoZufP0uhooO3mHDAKGNZB5HLP9HYYb+LAfKkUmd
    Recovery Key 5: L169hHj3DMpphGsOnS8TEz3Febvdx3vsG3Xr8kGWdUtW
    
    Initial Root Token: s.AWnDagUkKNNbvkENiL72wysn
    
    Success! Vault is initialized
    
    Recovery key initialized with 5 key shares and a key threshold of 3. Please
    securely distribute the key shares printed above.
    
    ```
    Recovery Key 1: iz1XWxe4CM+wrOGqRCx8ex8kB2XvGJEdfjhXFC+MA6Rc
    Recovery Key 2: rKZETr6IAy686IxfO3ZBKXPDAOkkwkpSepIME+bjeUT7
    Recovery Key 3: 4XA/KJqFOm+jzbBkKQuRVePEYPrQe3H3TmFVmdlUjRFv
    Recovery Key 4: lfnaYoZufP0uhooO3mHDAKGNZB5HLP9HYYb+LAfKkUmd
    Recovery Key 5: L169hHj3DMpphGsOnS8TEz3Febvdx3vsG3Xr8kGWdUtW
    
    Initial Root Token: s.AWnDagUkKNNbvkENiL72wysn
    
    Success! Vault is initialized
    
    Recovery key initialized with 5 key shares and a key threshold of 3. Please
    securely distribute the key shares printed above.
    ```
    
    Note
    
    The initialization generates **recovery keys** (instead of **unseal keys**) when using auto-unseal. Some Vault operations still require Shamir keys. For example, to [regenerate a root token](https://developer.hashicorp.com/vault/tutorials/policies/policies), each key holder must enter their recovery key. Similar to unseal keys, you can specify the number of recovery keys and the threshold using the `-recovery-shares` and `-recovery-threshold` flags. It is strongly recommended to [initialize Vault with PGP](https://developer.hashicorp.com/vault/docs/concepts/pgp-gpg-keybase#initializing-with-pgp).
    
7.  Run `vault status` for Vault 2 server to verify the initialization and seal status.
    
    $ VAULT\_ADDR=http://127.0.0.1:8100 vault status
    
    Key                      Value
    \---                      -----
    Recovery Seal Type       shamir
    Initialized              true
    Sealed                   false
    Total Recovery Shares    5
    Threshold                3
    # ...snip...
    
    ```
    $ VAULT_ADDR=http://127.0.0.1:8100 vault status
    
    Key                      Value
    ---                      -----
    Recovery Seal Type       shamir
    Initialized              true
    Sealed                   false
    Total Recovery Shares    5
    Threshold                3
    # ...snip...
    ```
    
    Notice that it shows `Total Recovery Shares` instead of `Total Shares`. The transit secrets engine is solely responsible for protecting the root key of **Vault 2**.
    

## [](https://developer.hashicorp.com/vault/tutorials/auto-unseal/autounseal-transit#step-3-verify-auto-unseal)Step 3: Verify auto-unseal

When you stop and start the Vault 2 server, it comes up in the `unsealed` state and ready for operations.

1.  To verify that **Vault 2** gets automatically unseal, press **Ctrl + C** to stop the Vault 2 server where it is running.
    
    ...snip...
    \[INFO\]  core.cluster-listener: rpc listeners successfully shut down
    \[INFO\]  core: cluster listeners successfully shut down
    \[INFO\]  core: vault is sealed
    
    ```
    ...snip...
    [INFO]  core.cluster-listener: rpc listeners successfully shut down
    [INFO]  core: cluster listeners successfully shut down
    [INFO]  core: vault is sealed
    ```
    
    Vault 2 is now sealed.
    
    When you try to check the Vault status, it returns the "connection refused" message.
    
    $ VAULT\_ADDR=http://127.0.0.1:8100 vault status
    
    Error checking seal status: Get "http://127.0.0.1:8100/v1/sys/seal-status": dial
    tcp 127.0.0.1:8100: connect: connection refused
    
    ```
    $ VAULT_ADDR=http://127.0.0.1:8100 vault status
    
    Error checking seal status: Get "http://127.0.0.1:8100/v1/sys/seal-status": dial
    tcp 127.0.0.1:8100: connect: connection refused
    ```
    
2.  Press the upper-arrow key, and execute the `vault server -config=config-autounseal.hcl` command again to start Vault 2 and see what happens.
    
    $ vault server -config=config-autounseal.hcl
    
    \==> Vault server configuration:
    
                    Seal Type: transit
              Transit Address: $VAULT\_ADDR
            Transit Key Name: autounseal
          Transit Mount Path: transit/
                          Cgo: disabled
                  Listener 1: tcp (addr: "0.0.0.0:8100", cluster address: "0.0.0.0:8101", max\_request\_duration: "1m30s", max\_request\_size: "33554432", tls: "disabled")
                    Log Level: info
                        Mlock: supported: true, enabled: false
                      Storage: file
                      Version: Vault v1.1.0
                  Version Sha: 36aa8c8dd1936e10ebd7a4c1d412ae0e6f7900bd
    
    \==> Vault server started! Log data will stream in below:
    
    \[WARN\]  no \`api\_addr\` value specified in config or in VAULT\_API\_ADDR; falling back to detection if possible, but this value should be manually set
    \[INFO\]  core: stored unseal keys supported, attempting fetch
    \[INFO\]  core: vault is unsealed
    # ...snip...
    
    ```
    $ vault server -config=config-autounseal.hcl
    
    ==> Vault server configuration:
    
                    Seal Type: transit
              Transit Address: $VAULT_ADDR
            Transit Key Name: autounseal
          Transit Mount Path: transit/
                          Cgo: disabled
                  Listener 1: tcp (addr: "0.0.0.0:8100", cluster address: "0.0.0.0:8101", max_request_duration: "1m30s", max_request_size: "33554432", tls: "disabled")
                    Log Level: info
                        Mlock: supported: true, enabled: false
                      Storage: file
                      Version: Vault v1.1.0
                  Version Sha: 36aa8c8dd1936e10ebd7a4c1d412ae0e6f7900bd
    
    ==> Vault server started! Log data will stream in below:
    
    [WARN]  no `api_addr` value specified in config or in VAULT_API_ADDR; falling back to detection if possible, but this value should be manually set
    [INFO]  core: stored unseal keys supported, attempting fetch
    [INFO]  core: vault is unsealed
    # ...snip...
    ```
    
    Notice that the Vault server is already unsealed. The **Transit Address** uses the Vault 1 address and is listening on port 8200 (`$VAULT_ADDR`).
    
3.  Check the Vault 2 server status.
    
    $ VAULT\_ADDR=http://127.0.0.1:8100 vault status
    
    Key                      Value
    \---                      -----
    Recovery Seal Type       shamir
    Initialized              true
    Sealed                   false
    Total Recovery Shares    5
    Threshold                3
    # ...snip...
    
    ```
    $ VAULT_ADDR=http://127.0.0.1:8100 vault status
    
    Key                      Value
    ---                      -----
    Recovery Seal Type       shamir
    Initialized              true
    Sealed                   false
    Total Recovery Shares    5
    Threshold                3
    # ...snip...
    ```
    
    Vault 2 is automatically unsealed.
    
4.  Now, examine the audit log in **Vault 1**.
    
    $ tail -f audit.log | jq
    
    # ...snip...
    "request": {
      "id": "a46719eb-eee0-92a4-2da6-6c7de77fd410",
      "operation": "update",
      "client\_token": "hmac-sha256:ce8613487054dadb36a9d08da1f5a4bbee2fbfc1ef1ec5ebdeec696df7823e69",
      "client\_token\_accessor": "hmac-sha256:f3b6cb798605835e8a00bafa9e0e16fc0534b8923b31e499f2c8e694f6b69158",
      "namespace": {
        "id": "root",
        "path": ""
      },
      "path": "transit/decrypt/autounseal",
        # ...snip...
      "remote\_address": "127.0.0.1",
      "wrap\_ttl": 0,
      "headers": {}
    },
    # ...snip...
    }
    
    ```
    $ tail -f audit.log | jq
    
    # ...snip...
    "request": {
      "id": "a46719eb-eee0-92a4-2da6-6c7de77fd410",
      "operation": "update",
      "client_token": "hmac-sha256:ce8613487054dadb36a9d08da1f5a4bbee2fbfc1ef1ec5ebdeec696df7823e69",
      "client_token_accessor": "hmac-sha256:f3b6cb798605835e8a00bafa9e0e16fc0534b8923b31e499f2c8e694f6b69158",
      "namespace": {
        "id": "root",
        "path": ""
      },
      "path": "transit/decrypt/autounseal",
        # ...snip...
      "remote_address": "127.0.0.1",
      "wrap_ttl": 0,
      "headers": {}
    },
    # ...snip...
    }
    ```
    
    You should see an `update` request against the `transit/decrypt/autounseal` path. The `remote_address` is `127.0.0.1` in this example since Vault 1 and Vault 2 are both running locally. If the Vault 2 is running on a different host, the audit log will show the IP address of the Vault 2 host.
    

Warning

If a security incident forces you to seal the Vault server using the `vault operator seal` command, it requires the threshold number of **recovery keys** to unseal Vault and bring it back to operation.

## [](https://developer.hashicorp.com/vault/tutorials/auto-unseal/autounseal-transit#clean-up)Clean up

1.  Execute the following command to stop the Vault servers.
    
    $ pgrep -f vault | xargs kill
    
    ```
    $ pgrep -f vault | xargs kill
    ```
    
2.  Unset the `VAULT_TOKEN` and `VAULT_ADDR` environment variables.
    
    $ unset VAULT\_TOKEN VAULT\_ADDR
    
    ```
    $ unset VAULT_TOKEN VAULT_ADDR
    ```
    
3.  Delete the generated files.
    
    $ rm config-autounseal.hcl vault-1.log audit.log wrapping-token.txt
    
    ```
    $ rm config-autounseal.hcl vault-1.log audit.log wrapping-token.txt
    ```
    
4.  Delete the raft directory.
    
    $ rm -r vault/
    
    ```
    $ rm -r vault/
    ```
    

## [](https://developer.hashicorp.com/vault/tutorials/auto-unseal/autounseal-transit#help-and-reference)Help and reference

*   [Recommended Pattern for Stateless Vault for Transit Auto Unseal](https://developer.hashicorp.com/vault/tutorials/recommended-patterns/pattern-auto-unseal)
*   [Seal Migration](https://developer.hashicorp.com/vault/docs/concepts/seal#seal-migration)
*   [Seal/Unseal](https://developer.hashicorp.com/vault/docs/concepts/seal)
*   [Configuration: `transit` Seal](https://developer.hashicorp.com/vault/docs/configuration/seal/transit)
*   [Vault 1.1: Secret Caching with Vault Agent and Other New Features](https://www.hashicorp.com/resources/vault-1-1-secret-caching-with-vault-agent-other-new-features)
*   [Periodic Tokens/TTL](https://developer.hashicorp.com/vault/docs/concepts/tokens#token-time-to-live-periodic-tokens-and-explicit-max-ttls)
