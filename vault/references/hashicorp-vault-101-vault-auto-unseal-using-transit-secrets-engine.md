#  hashicorp-vault-101-vault-auto-unseal-using-transit-secrets-engine

## Intrduction

Vault is unsealed by providing 3 out of the 5 generated key shares using `vault operator unseal`. There is no specific order required for unsealing Vault, and any three of the generated unseal keys can be used to successfully unseal it.

\[root@ip\-172\-31\-28\-77 ~\]\# vault operator unseal WJY5CxVteFIZxyWz6sHE+jk2y7U/yYHdmEXp8feucEG+  
Key                Value  
\---                -----  
Seal Type          shamir  
Initialized        true  
Sealed             true  
Total Shares       5  
Threshold          3  
Unseal Progress    1/3  
Unseal Nonce       6bf697ce-e547-3cb8-1c69-6aa102596af9  
Version            1.15.6  
Build Date         2024\-02\-28T17:07:34Z  
Storage Type       file  
HA Enabled         false  
\[root@ip\-172\-31\-28\-77 ~\]\# vault operator unseal Iyyq+sTorTIEuMD3qLMkPX8Z/rAbFDNpXsTfg+fGI1mE  
Key                Value  
\---                -----  
Seal Type          shamir  
Initialized        true  
Sealed             true  
Total Shares       5  
Threshold          3  
Unseal Progress    2/3  
Unseal Nonce       6bf697ce-e547-3cb8-1c69-6aa102596af9  
Version            1.15.6  
Build Date         2024\-02\-28T17:07:34Z  
Storage Type       file  
HA Enabled         false  
\[root@ip\-172\-31\-28\-77 ~\]\# vault operator unseal O0J67/PQDFESb90Eeh0NBbjsERd1ihVAOZst9L0khNSy  
Key             Value  
\---             -----  
Seal Type       shamir  
Initialized     true  
Sealed          false  
Total Shares    5  
Threshold       3  
Version         1.15.6  
Build Date      2024\-02\-28T17:07:34Z  
Storage Type    file  
Cluster Name    vault-cluster-a9458740  
Cluster ID      df294ca6-1faa-3ad8-704f-05683f4f962d  
HA Enabled      false

Now, verify the Vault status to ensure that the sealed state is false and it is initialized

\[root@ip\-172\-31\-28\-77 ~\]\# vault status  
Key             Value  
\---             -----  
Seal Type       shamir  
Initialized     true  
Sealed          false  
Total Shares    5  
Threshold       3  
Version         1.15.6  
Build Date      2024\-02\-28T17:07:34Z  
Storage Type    file  
Cluster Name    vault-cluster-a9458740  
Cluster ID      df294ca6-1faa-3ad8-704f-05683f4f962d  
HA Enabled      false  
\[root@ip\-172\-31\-28\-77 ~\]#

Access Vault by authenticating with the initial root token obtained during initialization

\[root@ip-172-31-28-77 ~\]\# vault login hvs.RKH9hOXD3aHvtJTFgkSQv68s  
Success! You are now authenticated. The token information displayed below  
is already stored in the token helper. You do NOT need to run "vault login"  
again. Future Vault requests will automatically use this token.  
  
Key                  Value  
\---                  -----  
token                hvs.RKH9hOXD3aHvtJTFgkSQv68s  
token\_accessor       spYtE1ZifnJP8uy8CppnnK1h  
token\_duration       ∞  
token\_renewable      false  
token\_policies       \["root"\]  
identity\_policies    \[\]  
policies             \["root"\]  
\[root@ip-172-31-28-77 ~\]#

Enable the `transit` secrets engine

\[root@ip\-172\-31\-28\-77 ~\]\# vault secrets enable transit  
Success! Enabled the transit secrets engine at: transit/  
\[root@ip\-172\-31\-28\-77 ~\]#

create an encryption key named, “autounseal”

\[root@ip\-172\-31\-28\-77 ~\]\# vault write -f transit/keys/autounseal  
Key                       Value  
\---                       -----  
allow\_plaintext\_backup    false  
auto\_rotate\_period        0s  
deletion\_allowed          false  
derived                   false  
exportable                false  
imported\_key              false  
keys                      map\[1:1724972716\]  
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
\[root@ip\-172\-31\-28\-77 ~\]#

Create file called autounseal-policy.hcl and

\[root@ip-172-31-28-77 ~\]\# vi autounseal-policy.hcl  
\[root@ip-172-31-28-77 ~\]\# cat autounseal-policy.hcl  
path "transit/encrypt/autounseal" {  
   capabilities = \[ "update" \]  
}  
  
path "transit/decrypt/autounseal" {  
   capabilities = \[ "update" \]  
}  
\[root@ip-172-31-28-77 ~\]#

Create a policy named `autounseal` which permits `update` against `transit/encrypt/autounseal` and `transit/decrypt/autounseal` paths

\[root@ip\-172\-31\-28\-77 ~\]\# vault policy write autounseal autounseal-policy.hcl  
Success! Uploaded policy: autounseal  
\[root@ip\-172\-31\-28\-77 ~\]#

Create a **client token** with autounseal policy attached and response wrap it with TTL of 120 seconds

\[root@ip-172-31-28-77 ~\]\# vault token create -policy="autounseal" -wrap-ttl=120 -period=24h  
Key                              Value  
\---                              \-----  
wrapping\_token:                  hvs.CAESIFpdGmvUpeV7ZUrPJpmHlhAPS\_LbCiAO0eMtkvMy0tPzGh4KHGh2cy5VQ2pMNlJ4WFJVU2lwME42Zm1FMUFmeTQ  
wrapping\_accessor:               Qb4UJdQBWjG87DlAAGZ7hJfG  
wrapping\_token\_ttl:              2m  
wrapping\_token\_creation\_time:    2024-08-29 23:28:55.631122359 +0000 UTC  
wrapping\_token\_creation\_path:    auth/token/create  
wrapped\_accessor:                u3QiCxX0FRdiPqRUELQUAT2y  
\[root@ip-172-31-28-77 ~\]#

Unwrap the token that was created with the auto-unseal policy

\[root@ip-172-31-28-77 ~\]\# vault unwrap hvs.CAESIFpdGmvUpeV7ZUrPJpmHlhAPS\_LbCiAO0eMtkvMy0tPzGh4KHGh2cy5VQ2pMNlJ4WFJVU2lwME42Zm1FMUFmeTQ  
Key                  Value  
\---                  -----  
token                hvs.CAESIPxNqzQU\_KfIWblgQKYeu\_7cCzQ8IV4VBf-eaDW2R1b1Gh4KHGh2cy5vb0ZsbTVtRmw5cmVCYjUzWFZOc0ZrVEg  
token\_accessor       u3QiCxX0FRdiPqRUELQUAT2y  
token\_duration       24h  
token\_renewable      true  
token\_policies       \["autounseal" "default"\]  
identity\_policies    \[\]  
policies             \["autounseal" "default"\]  
\[root@ip-172-31-28-77 ~\]#

### 3.Configure auto-unseal (Vault 2)

Press enter or click to view image in full size

![](Hashicorp%20Vault%20101%E2%80%938_Vault%20Auto-unseal%20using%20Transit%20secrets%20engine%20_%20by%20Mahendran%20Selvakumar%20_%20Devopstronaut_files/0_E7E5onB-j8_QAG3o.png)

Verify the vault status on Vault 2 server

\[root@ip\-172\-31\-31\-159 vault.d\]\# vault status  
Key                Value  
\---                -----  
Seal Type          shamir  
Initialized        false  
Sealed             true  
Total Shares       0  
Threshold          0  
Unseal Progress    0/0  
Unseal Nonce       n/a  
Version            1.15.6  
Build Date         2024\-02\-28T17:07:34Z  
Storage Type       file  
HA Enabled         false  
\[root@ip\-172\-31\-31\-159 vault.d\]#

Set the `VAULT_TOKEN` environment variable to the client token you unwrapped from Vault 1 Server

\[root@ip-172-31-31-159 vault.d\]\# export VAULT\_TOKEN=hvs.CAESIPxNqzQU\_KfIWblgQKYeu\_7cCzQ8IV4VBf-eaDW2R1b1Gh4KHGh2cy5vb0ZsbTVtRmw5cmVCYjUzWFZOc0ZrVEg  
\[root@ip-172-31-31-159 vault.d\]#

Create a server configuration file (`autounseal.hcl`) to start a second Vault instance

\[root@ip-172-31-31-159 vault.d\]\# vi autounseal.hcl  
\[root@ip-172-31-31-159 vault.d\]\# cat autounseal.hcl  
disable\_mlock = true  
ui=true  
  
storage "file" {  
   path    = "/data/vault-2"  
}  
  
listener "tcp" {  
  address     = "127.0.0.1:8100"  
  tls\_disable = "true"  
}  
  
seal "transit" {  
  address = "http://172.31.28.77:8200"  
  disable\_renewal = "false"  
  key\_name = "autounseal"  
  mount\_path = "transit/"  
  tls\_skip\_verify = "true"  
}  
  
api\_addr = "http://127.0.0.1:8100"  
cluster\_addr = "https://127.0.0.1:8101"  
\[root@ip-172-31-31-159 vault.d\]#

Create the raft path directory as configured in the storage stanza

\[root@ip-172-31-31-159 ~\]\# mkdir -p /data/vault-2  
\[root@ip-172-31-31-159 ~\]

Start the server using the configuration

\[root@ip-172-31-31-159 vault.d\]\# vault server -config=autounseal.hcl  
\==> Vault server configuration:  
  
Administrative Namespace:  
             Api Address: http://127.0.0.1:8100  
                     Cgo: disabled  
         Cluster Address: https://127.0.0.1:8101  
   Environment Variables: BASH\_FUNC\_which%%, GODEBUG, HISTCONTROL, HISTSIZE, HOME, HOSTNAME, LANG, LESSOPEN, LOGNAME, LS\_COLORS, MAIL, OLDPWD, PATH, PWD, SHELL, SHLVL, SYSTEMD\_COLORS, S\_COLORS, TERM, USER, VAULT\_ADDR, VAULT\_TOKEN, \_, which\_declare  
              Go Version: go1.21.7  
              Listener 1: tcp (addr: "127.0.0.1:8100", cluster address: "127.0.0.1:8101", max\_request\_duration: "1m30s", max\_request\_size: "33554432", tls: "disabled")  
               Log Level:  
                   Mlock: supported: true, enabled: false  
           Recovery Mode: false  
                 Storage: file  
                 Version: Vault v1.15.6, built 2024-02-28T17:07:34Z  
             Version Sha: 615cf6f1dce9aa91bc2035ce33b9f689952218f0  
  
\==> Vault server started! Log data will stream in below:  
  
2024-08-29T23:39:18.297Z \[INFO\]  proxy environment: http\_proxy="" https\_proxy="" no\_proxy=""  
2024-08-29T23:41:05.082Z \[INFO\]  incrementing seal generation: generation=1  
2024-08-29T23:41:05.082Z \[INFO\]  core: Initializing version history cache for core  
2024-08-29T23:41:05.082Z \[INFO\]  events: Starting event system  
2024-08-29T23:41:05.084Z \[INFO\]  core: stored unseal keys supported, attempting fetch  
2024-08-29T23:41:05.084Z \[WARN\]  failed to unseal core: error="stored unseal keys are supported, but none were found"  
2024-08-29T23:41:10.084Z \[INFO\]  core: stored unseal keys supported, attempting fetch  
2024-08-29T23:41:10.085Z \[WARN\]  failed to unseal core: error="stored unseal keys are supported, but none were found"  
2024-08-29T23:41:15.085Z \[INFO\]  core: stored unseal keys supported, attempting fetch  
2024-08-29T23:41:15.085Z \[WARN\]  failed to unseal core: error="stored unseal keys are supported, but none were found"  
2024-08-29T23:41:20.087Z \[INFO\]  core: stored unseal keys supported, attempting fetch  
2024-08-29T23:41:20.087Z \[WARN\]  failed to unseal core: error="stored unseal keys are supported, but none were found"  
2024-08-29T23:41:25.087Z \[INFO\]  core: stored unseal keys supported, attempting fetch  
2024-08-29T23:41:25.088Z \[WARN\]  failed to unseal core: error="stored unseal keys are supported, but none were found"  
2024-08-29T23:41:30.088Z \[INFO\]  core: stored unseal keys supported, attempting fetch  
2024-08-29T23:41:30.089Z \[WARN\]  failed to unseal core: error="stored unseal keys are supported, but none were found

Login to vaultServer 2 server in another terminal

mahendranselvakumar@Mahendrans-MBP Downloads % ssh -i "Vault.pem" ec2-user@ec2-34\-249\-192\-8.eu-west-1.compute.amazonaws.com  
   ,     #\_  
   ~\\\_  ####\_        Amazon Linux 2023  
  ~~  \\\_#####\\  
  ~~     \\###|  
  ~~       \\#/ \_\_\_   https://aws.amazon.com/linux/amazon-linux-2023  
   ~~       V~' '\->  
    ~~~         /  
      ~~.\_.   \_/  
         \_/ \_/  
       \_/m/'  
Last login: Thu Aug 29 23:21:04 2024 from 176.248.232.84  
\[ec2-user@ip-172-31-31-159 ~\]$ sudo su -  
Last login: Thu Aug 29 23:21:07 UTC 2024 on pts/3  
\[root@ip-172\-31\-31\-159 ~\]#

Set an environment variable for the `vault` CLI to address the Vault server and initialise the Vault

\[root@ip-172-31-31-159 ~\]\# export VAULT\_ADDR=http://127.0.0.1:8100  
\[root@ip-172-31-31-159 ~\]\# vault operator init  
Recovery Key 1: lp/Xr34271ra/u5TKOm3JquR87EhMybgMHgrUnwN/CRY  
Recovery Key 2: AB9CV+gLU7DmsbErCn8WgegMVQX/52yP1JA8jnLMyQNN  
Recovery Key 3: LUTXwjIpUiBNT8nqqr0XL2HxF1SG236TrY4LmsghKzr4  
Recovery Key 4: AGBaTU9mmKv4EzHf+uwa+TjSCIWS7B88LMtuKqLg7KVF  
Recovery Key 5: oqu9KeFfADKbShIWWrKWFkgdcp5fzhSJyafMltYogThq  
  
Initial Root Token: hvs.6zMfyYoiQF1G4f7QhDFDyVes  
  
Success! Vault is initialized  
  
Recovery key initialized with 5 key shares and a key threshold of 3. Please  
securely distribute the key shares printed above.  
\[root@ip-172-31-31-159 ~\]#

Verify the Vault status and it is now successfully initialized and unsealed.

\[root@ip\-172\-31\-31\-159 ~\]\# vault status  
Key                      Value  
\---                      -----  
Seal Type                transit  
Recovery Seal Type       shamir  
Initialized              true  
Sealed                   false  
Total Recovery Shares    5  
Threshold                3  
Version                  1.15.6  
Build Date               2024\-02\-28T17:07:34Z  
Storage Type             file  
Cluster Name             vault-cluster-2b7dea5f  
Cluster ID               700afa5c-3c25-778c-33be-8ae21a38d838  
HA Enabled               false  
\[root@ip\-172\-31\-31\-159 ~\]#

### 4.Verify Vault auto-unseal

press Ctrl + C to stop the Vault 2 server where it is running

^C==> Vault shutdown triggered  
2024-08-29T23:47:49.859Z \[INFO\]  core: marked as sealed  
2024-08-29T23:47:49.859Z \[INFO\]  core: pre-seal teardown starting  
2024-08-29T23:47:49.859Z \[INFO\]  rollback: stopping rollback manager  
2024-08-29T23:47:49.859Z \[INFO\]  core: pre-seal teardown complete  
2024-08-29T23:47:49.859Z \[INFO\]  core: stopping cluster listeners  
2024-08-29T23:47:49.859Z \[INFO\]  core.cluster-listener: forwarding rpc listeners stopped  
2024-08-29T23:47:50.229Z \[INFO\]  core.cluster-listener: rpc listeners successfully shut down  
2024-08-29T23:47:50.229Z \[INFO\]  core: cluster listeners successfully shut down  
2024-08-29T23:47:50.229Z \[INFO\]  core: vault is sealed  
\[root@ip-172-31-31-159 vault.d\]#

Check the Vault status and you should see that the seal type is Shamir, the sealed state is true, and initialized is false

\[root@ip\-172\-31\-31\-159 vault.d\]\# vault status  
Key                Value  
\---                -----  
Seal Type          shamir  
Initialized        false  
Sealed             true  
Total Shares       0  
Threshold          0  
Unseal Progress    0/0  
Unseal Nonce       n/a  
Version            1.15.6  
Build Date         2024\-02\-28T17:07:34Z  
Storage Type       file  
HA Enabled         false  
\[root@ip\-172\-31\-31\-159 vault.d\]#

Execute the `vault server -config=autounseal.hcl` command again to start Vault Server 2

\[root@ip-172-31-31-159 vault.d\]\# vault server -config=autounseal.hcl  
\==> Vault server configuration:  
  
Administrative Namespace:  
             Api Address: http://127.0.0.1:8100  
                     Cgo: disabled  
         Cluster Address: https://127.0.0.1:8101  
   Environment Variables: BASH\_FUNC\_which%%, GODEBUG, HISTCONTROL, HISTSIZE, HOME, HOSTNAME, LANG, LESSOPEN, LOGNAME, LS\_COLORS, MAIL, OLDPWD, PATH, PWD, SHELL, SHLVL, SYSTEMD\_COLORS, S\_COLORS, TERM, USER, VAULT\_ADDR, VAULT\_TOKEN, \_, which\_declare  
              Go Version: go1.21.7  
              Listener 1: tcp (addr: "127.0.0.1:8100", cluster address: "127.0.0.1:8101", max\_request\_duration: "1m30s", max\_request\_size: "33554432", tls: "disabled")  
               Log Level:  
                   Mlock: supported: true, enabled: false  
           Recovery Mode: false  
                 Storage: file  
                 Version: Vault v1.15.6, built 2024-02-28T17:07:34Z  
             Version Sha: 615cf6f1dce9aa91bc2035ce33b9f689952218f0  
  
\==> Vault server started! Log data will stream in below:  
  
2024-08-29T23:50:52.084Z \[INFO\]  proxy environment: http\_proxy="" https\_proxy="" no\_proxy=""  
2024-08-29T23:50:52.092Z \[INFO\]  incrementing seal generation: generation=1  
2024-08-29T23:50:52.093Z \[INFO\]  core: Initializing version history cache for core  
2024-08-29T23:50:52.093Z \[INFO\]  events: Starting event system  
2024-08-29T23:50:52.095Z \[INFO\]  core: stored unseal keys supported, attempting fetch  
2024-08-29T23:50:52.097Z \[INFO\]  core.cluster-listener.tcp: starting listener: listener\_address=127.0.0.1:8101  
2024-08-29T23:50:52.097Z \[INFO\]  core.cluster-listener: serving cluster requests: cluster\_listen\_address=127.0.0.1:8101  
2024-08-29T23:50:52.097Z \[INFO\]  core: post-unseal setup starting  
2024-08-29T23:50:52.098Z \[INFO\]  core: loaded wrapping token key  
2024-08-29T23:50:52.098Z \[INFO\]  core: successfully setup plugin runtime catalog  
2024-08-29T23:50:52.098Z \[INFO\]  core: successfully setup plugin catalog: plugin-directory=""  
2024-08-29T23:50:52.100Z \[INFO\]  core: successfully mounted: type=system version="v1.15.6+builtin.vault" path=sys/ namespace="ID: root. Path: "  
2024-08-29T23:50:52.100Z \[INFO\]  core: successfully mounted: type=identity version="v1.15.6+builtin.vault" path=identity/ namespace="ID: root. Path: "  
2024-08-29T23:50:52.100Z \[INFO\]  core: successfully mounted: type=cubbyhole version="v1.15.6+builtin.vault" path=cubbyhole/ namespace="ID: root. Path: "  
2024-08-29T23:50:52.102Z \[INFO\]  core: successfully mounted: type=token version="v1.15.6+builtin.vault" path=token/ namespace="ID: root. Path: "  
2024-08-29T23:50:52.102Z \[INFO\]  rollback: Starting the rollback manager with 256 workers  
2024-08-29T23:50:52.102Z \[INFO\]  core: restoring leases  
2024-08-29T23:50:52.104Z \[INFO\]  expiration: lease restore complete  
2024-08-29T23:50:52.104Z \[INFO\]  rollback: starting rollback manager  
2024-08-29T23:50:52.104Z \[INFO\]  identity: entities restored  
2024-08-29T23:50:52.104Z \[INFO\]  identity: groups restored  
2024-08-29T23:50:52.104Z \[INFO\]  core: usage gauge collection is disabled  
2024-08-29T23:50:52.109Z \[INFO\]  core: post-unseal setup complete  
2024-08-29T23:50:52.109Z \[INFO\]  core: vault is unsealed  
2024-08-29T23:50:52.109Z \[INFO\]  core: unsealed with stored key

Check the Vault status and you should see that the seal type is transit,the sealed state is false, and initialized is true

\[root@ip\-172\-31\-31\-159 ~\]\# vault status  
Key                      Value  
\---                      -----  
Seal Type                transit  
Recovery Seal Type       shamir  
Initialized              true  
Sealed                   false  
Total Recovery Shares    5  
Threshold                3  
Version                  1.15.6  
Build Date               2024\-02\-28T17:07:34Z  
Storage Type             file  
Cluster Name             vault-cluster-2b7dea5f  
Cluster ID               700afa5c-3c25-778c-33be-8ae21a38d838  
HA Enabled               false  
\[root@ip\-172\-31\-31\-159 ~\]#

### Conclusion:

Utilizing auto-unseal with the Transit Secret Engine in HashiCorp Vault significantly enhances security and efficiency. By integrating with a key management system, this feature automates the process of key retrieval and management, eliminating the need for manual intervention. This not only minimizes the risk of human error but also streamlines operations, making it easier to maintain a secure and resilient infrastructure. Adopting auto-unseal with the Transit Secret Engine allows organizations to focus more on their core objectives while ensuring that their sensitive data remains protected and properly managed.

