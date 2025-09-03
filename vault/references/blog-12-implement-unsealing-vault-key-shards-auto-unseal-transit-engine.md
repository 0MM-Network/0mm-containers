# Blog 12. Implement Unsealing HashiCorp Vault: Key Shards, Auto-Unseal, Transit Auto Unseal. | by Rakshantha M

**Commencement:**

In this blog, well explore one of the fundamental security features of HashiCorp Vault: the unsealing process. When Vault is initialized, it secures its data using a Master Key, which is stored in a protected, encrypted state. To ensure this key and the underlying data are safe, Vault begins in a sealed state, meaning that access to the data is restricted until the Vault is unsealed.

Unsealing is essential to safeguarding sensitive information and controlling access, especially after a Vault restart or when it is brought online, as administrators must provide specific credentials to unlock the Vault.

The unsealing process can be handled in several ways, each tailored to different operational needs and levels of security. In this guide, we will cover three primary methods of unsealing.

> **Manual Unseal Using Key Shards**:

In this approach, Vault divides the Master Key generated during initialization into multiple key shards using Shamirs Secret Sharing Algorithm.

A predefined number of key shards, known as a quorum, must be combined to unseal Vault. This ensures a secure, manual method of controlling access, as no single person has full access to the Master Key. By requiring multiple key holders to contribute their shards, Vaults security is reinforced, preventing unauthorized access to sensitive data.

Press enter or click to view image in full size

![](Blog%2012.%20Implement%20Unsealing%20HashiCorp%20Vault_%20Key%20Shards,%20Auto-Unseal,%20Transit%20Auto%20Unseal.%20_%20by%20Rakshantha%20M%20_%20Medium_files/1_xm_flsZk84hfy-DDUuFoKg_005.png)

```
## config.hcl file  
storage "raft" {  
  path    = "./vault/data"  
  node_id = "node1"  
}  
  
listener "tcp" {  
  address     = "0.0.0.0:8200"  
  tls_disable = "true"  
}  
  
disable_mlock = true  
  
api_addr = "http://52.55.138.203:8200"  
cluster_addr = "http://52.55.138.203:8201"  
ui = true
```

This configuration file sets up HashiCorp Vault to use the Raft storage backend, storing data in a local directory while defining network settings for the Vault API and cluster communication. It listens on all interfaces at port 8200 without TLS, with the UI enabled for user access.

## Start the Vault server using the settings defined in config.hcl.  

```  
ubuntu@ip-172-31-32-104:~$ mkdir -p ./vault/data  
vault server -config=config.hcl  
==> Vault server configuration:
  
Administrative Namespace:   
             Api Address: http://52.55.138.203:8200  
                     Cgo: enabled  
         Cluster Address: https://52.55.138.203:8201  
   Environment Variables: DBUS_SESSION_BUS_ADDRESS, HOME, LANG, LD_LIBRARY_PATH, LESSCLOSE, LESSOPEN, LOGNAME, LS_COLORS, PATH, PWD, SHELL, SHLVL, SNAP, SNAP_ARCH, SNAP_COMMON, SNAP_CONTEXT, SNAP_COOKIE, SNAP_DATA, SNAP_EUID, SNAP_INSTANCE_KEY, SNAP_INSTANCE_NAME, SNAP_LIBRARY_PATH, SNAP_NAME, SNAP_REAL_HOME, SNAP_REEXEC, SNAP_REVISION, SNAP_UID, SNAP_USER_COMMON, SNAP_USER_DATA, SNAP_VERSION, SSH_CLIENT, SSH_CONNECTION, SSH_TTY, TEMPDIR, TERM, TMPDIR, USER, XDG_DATA_DIRS, XDG_RUNTIME_DIR, XDG_SESSION_CLASS, XDG_SESSION_ID, XDG_SESSION_TYPE, _  
              Go Version: go1.22.8  
              Listener 1: tcp (addr: "0.0.0.0:8200", cluster address: "0.0.0.0:8201", disable_request_limiter: "false", max_request_duration: "1m30s", max_request_size: "33554432", tls: "disabled")  
               Log Level:   
                   Mlock: supported: true, enabled: false  
           Recovery Mode: false  
                 Storage: raft (HA available)  
                 Version: Vault v1.17.6   
```
  
Set the environment variable to specify the Vault server's address.  

```
export VAULT_ADDR='http://127.0.0.1:8200'
```

Steps:

**Initialization:**

*   Status of Vault before initialization, it will show that Vault is not initialized and is sealed
*   When Vault is initialized, it generates a Master Key and splits it into a predefined number of shards (N). To unseal Vault, a subset of these shards (K) is required (e.g., 3 of 5 shards).

```
$ ubuntu@ip-172-31-32-104:~$ vault status  
Key                Value  
---                -----  
Seal Type          shamir  
Initialized        false  
Sealed             true  
Total Shares       0  
Threshold          0  
Unseal Progress    0/0  
Unseal Nonce       n/a  
Version            1.17.6  
Build Date         n/a  
Storage Type       raft  
HA Enabled         true  
  
$ ubuntu@ip-172-31-32-104:~$ vault operator init -key-shares=5 -key-threshold=3  
Unseal Key 1: g241QWhys6H6SH2vx+1kOZJSPGAQur4iWZNqOJk1Ku/f  
Unseal Key 2: WCLcHK8n6mx6JIc2LvUdSC4gHzpnanqxCVj6C1orHn7z  
Unseal Key 3: rnqshnIbMXZvZd8Jmiof0m9o9WQ56FT+APIfhA/jVJfs  
Unseal Key 4: Eq0YF2IghUVNaUEM8R9GeDFbTzPpZyWd2cC+CDQb76p2  
Unseal Key 5: nNsErcAKZmVQ9J9nPyQh3T/qy6lKbejpSSPHOSW8GilA  
```

Initial Root Token: hvs.3JclHlS3AfD1H6lUPF3gbKsW  
  
Vault initialized with 5 key shares and a key threshold of 3. Please securely  
distribute the key shares printed above. When the Vault is re-sealed,  
restarted, or stopped, you must supply at least 3 of these keys to unseal it  
before it can start servicing requests.  
  
Vault does not store the generated root key. Without at least 3 keys to  
reconstruct the root key, Vault will remain permanently sealed!  
  
It is possible to generate new unseal keys, provided you have a quorum of  
existing unseal keys shares. See "vault operator rekey" for more information.  

```
$ ubuntu@ip-172-31-32-104:~$ vault status  
Key                Value  
---                -----  
Seal Type          shamir  
Initialized        true  
Sealed             true  
Total Shares       5  
Threshold          3  
Unseal Progress    0/3  
Unseal Nonce       n/a  
Version            1.17.6  
Build Date         n/a  
Storage Type       raft  
HA Enabled         true  
```

Distribute the unseal key shards securely to trusted operators, each responsible for their shard. When Vault is started or rebooted, it is sealed, and operators must manually provide the necessary key shards to unseal it.

**Accessing via UI:**

Once threshold unseal keys are provided it prompts for sign-in using various methods. Default method is token.

Once logged-in try to enable KV and AWS secrets engine and set a path to write key value pairs.

Its time to check the CLI part to verify,

```
$ ubuntu@ip-172-31-32-104:~$ vault status  
Key                     Value  
---                     -----  
Seal Type               shamir  
Initialized             true  
Sealed                  false  
Total Shares            5  
Threshold               3  
Version                 1.17.6  
Build Date              n/a  
Storage Type            raft  
Cluster Name            vault-cluster-1c2500cd  
Cluster ID              8a0631f2-99f9-901b-1d08-5d80239c96af  
HA Enabled              true  
HA Cluster              https://52.55.138.203:8201  
HA Mode                 active  
Active Since            2024-10-16T11:53:46.980635808Z  
Raft Committed Index    79  
Raft Applied Index      79  
  
$ ubuntu@ip-172-31-32-104:~$ vault login  
Token (will be hidden):   
Success! You are now authenticated. The token information displayed below  
is already stored in the token helper. You do NOT need to run "vault login"  
again. Future Vault requests will automatically use this token.  
  
Key                  Value  
---                  -----  
token                hvs.3JclHlS3AfD1H6lUPF3gbKsW  
token_accessor       NmQugy7LAbJnCINaGmieK5N4  
token_duration         
token_renewable      false  
token_policies       ["root"]  
identity_policies    []  
policies             ["root"]  
  
$ ubuntu@ip-172-31-32-104:~$ vault secrets list  
Path          Type         Accessor              Description  
----          ----         --------              -----------  
aws/          aws          aws_63c52993          n/a  
cubbyhole/    cubbyhole    cubbyhole_91b6dd0b    per-token private secret storage  
identity/     identity     identity_0b20f54e     identity store  
kv/           kv           kv_29cf17fa           n/a  
sys/          system       system_883b534b       system endpoints used for control, policy and debugging
```

**Pros & cons of Manual unseal:**

> **Auto-Unseal Mechanism**:

By default, Vault requires a manual unseal process, where key holders combine their shards to unlock Vault after a restart or failure. However, for enterprises that require **high availability** and **automation**, manually unsealing Vault can become cumbersome and inefficient.

This is where **Auto-Unseal** comes into play. Instead of requiring key holders to provide key shards, Vault leverages an external **Key Management System (KMS)** or **Hardware Security Module (HSM)** to store and retrieve the unseal keys.

Create KMS key named auto_unseal_kms in AWS with below configurations,

**Key type :** Symmetric

**Key spec :** SYMMETRIC_DEFAULT

**Key usage :** Encrypt and decrypt

**Origin :** AWS KMS

**Regionality :** Single-Region key

```
{  
    "Id": "key-consolepolicy-3",  
    "Version": "2012-10-17",  
    "Statement": [  
        {  
            "Sid": "Enable IAM User Permissions",  
            "Effect": "Allow",  
            "Principal": {  
                "AWS": "arn:aws:iam::650251704847:root"  
            },  
            "Action": "kms:\*",  
            "Resource": "\*"  
        },  
        {  
            "Sid": "Allow access for Key Administrators",  
            "Effect": "Allow",  
            "Principal": {  
                "AWS": "arn:aws:iam::650251704847:user/raksh"  
            },  
            "Action": [  
                "kms:Create\*",  
                "kms:Describe\*",  
                "kms:Enable\*",  
                "kms:List\*",  
                "kms:Put\*",  
                "kms:Update\*",  
                "kms:Revoke\*",  
                "kms:Disable\*",  
                "kms:Get\*",  
                "kms:Delete\*",  
                "kms:TagResource",  
                "kms:UntagResource",  
                "kms:ScheduleKeyDeletion",  
                "kms:CancelKeyDeletion",  
                "kms:RotateKeyOnDemand"  
            ],  
            "Resource": "\*"  
        },  
        {  
            "Sid": "Allow use of the key",  
            "Effect": "Allow",  
            "Principal": {  
                "AWS": "arn:aws:iam::650251704847:user/raksh"  
            },  
            "Action": [  
                "kms:Encrypt",  
                "kms:Decrypt",  
                "kms:ReEncrypt\*",  
                "kms:GenerateDataKey\*",  
                "kms:DescribeKey"  
            ],  
            "Resource": "\*"  
        },  
        {  
            "Sid": "Allow attachment of persistent resources",  
            "Effect": "Allow",  
            "Principal": {  
                "AWS": "arn:aws:iam::650251704847:user/raksh"  
            },  
            "Action": [  
                "kms:CreateGrant",  
                "kms:ListGrants",  
                "kms:RevokeGrant"  
            ],  
            "Resource": "\*",  
            "Condition": {  
                "Bool": {  
                    "kms:GrantIsForAWSResource": "true"  
                }  
            }  
        }  
    ]  
}
```

### Key Concepts of Auto-Unseal:

*   **Master Key**: This is the key Vault uses to decrypt the data encryption key (DEK) that protects all stored secrets.
*   **Key Management System (KMS)**: A cloud service or HSM that stores the master key and provides the key to Vault for automatic unsealing.
*   **Seal/Unseal Process**: In Auto-Unseal, the unseal keys are managed by the KMS, removing the need for manual key shard distribution.

1.  The logs indicate that Vault is initializing various components, including the Raft storage system and setting up default mounts like cubbyhole and identity.
2.  After an initial attempt to unseal using stored keys (which were not found), Vault enters an unsealed state successfully, indicating it can now accept operations.
3.  Vault performs post-unseal setup tasks, such as loading wrapping tokens, restoring leases, and starting the Raft active node, ultimately indicating that it is ready for operation.

## Transit Auto Unseal:

**Transit Auto-Unseal** is a feature in HashiCorp Vault that allows one Vault instance to automatically unseal another using the Transit Secrets Engine. By default, when Vault is restarted, it is sealed and requires a quorum of unseal keys to access secrets. This can create operational overhead, especially in dynamic environments where Vault instances are frequently restarted.

## Why Use Transit Auto-Unseal?

*   **Automation**: Reduces manual intervention by automating the unseal process.
*   **Cloud-Ready**: Essential for ephemeral environments where systems may frequently restart.
*   **Scalability**: Simplifies management in high-availability Vault setups.

## Use Cases for Transit Auto-Unseal

1.  **Dynamic Infrastructure**: In cloud environments with ephemeral instances, auto-unseal helps maintain seamless operations without manual input.
2.  **High Availability (HA)**: Ensures that Vault instances remain operational during failovers or maintenance.

Configure two Vault servers:

1.  **Primary Vault (KMS Vault)**: Acts as the KMS using the Transit engine.
2.  **Secondary Vault (Auto-Unsealing Vault)**: Automatically unseals itself using keys from the primary Vault.

```
# Install vault in primary node  
$ wget https://releases.hashicorp.com/vault/1.18.0/vault_1.18.0_linux_amd64.zip  

$ unzip vault_1.18.0_linux_amd64.zip  

$ sudo mv vault /usr/local/bin/  
  
$ vault --version  
  
$ sudo nano /etc/vault.d/vault.hcl  
  
storage "file" {  
  path = "/opt/vault/data"  
}  
  
listener "tcp" {  
  address     = "0.0.0.0:8200"  
  tls_disable = true  
}  
  
disable_mlock = true  
ui = true  
```  

``` 
$ vault server -config=/etc/vault.d/vault.hcl  
  
==> Vault server configuration:  
  
   Administrative Namespace:   
             Api Address: http://<PUBLIC_IP>:8200  
                     Cgo: disabled  
         Cluster Address: https://<PUBLIC_IP>:8201  
   Environment Variables: HOME, LANG, LOGNAME, LS_COLORS, MAIL, PATH, SHELL, TERM, USER  
              Go Version: go1.22.7  
              Listener 1: tcp (addr: "0.0.0.0:8200", cluster address: "0.0.0.0:8201", disable_request_limiter: "false", max_request_duration: "1m30s", max_request_size: "33554432", tls: "disabled")  
               Log Level: info  
                   Mlock: supported: true, enabled: false  
           Recovery Mode: false  
                 Storage: file  
                 Version: Vault v1.18.0, built 2024-10-08T09:12:52Z  
             Version Sha: 77f26ba561a4b6b1ccd5071b8624cefef7a72e84  
  
==> Vault server started! Log data will stream in below:  
  
2024-10-18T10:00:00.000Z [NFO]  proxy environment: http_proxy="" https_proxy="" no_proxy=""  
2024-10-18T10:00:00.000Z [NFO]  core: initializing storage  
2024-10-18T10:00:00.000Z [NFO]  core: loading configuration  
2024-10-18T10:00:00.000Z [NFO]  core: initializing listener  
2024-10-18T10:00:00.000Z [NFO]  core: unsealing vault  
2024-10-18T10:00:00.000Z [NFO]  seal: unseal process completed  
2024-10-18T10:00:00.000Z [NFO]  core: unseal complete  
```

```  
$ sudo nano /etc/systemd/system/vault.service  
[nit]  
Description="HashiCorp Vault - A tool for managing secrets"  
Documentation=https://developer.hashicorp.com/vault/docs  
Requires=network-online.target  
After=network-online.target  
ConditionFileNotEmpty=/etc/vault.d/vault.hcl  
StartLimitIntervalSec=60  
StartLimitBurst=3  
  
[ervice]  
Type=notify  
EnvironmentFile=/etc/vault.d/vault.env  
User=vault  
Group=vault  
ProtectSystem=full  
ProtectHome=read-only  
PrivateTmp=yes  
PrivateDevices=yes  
SecureBits=keep-caps  
AmbientCapabilities=CAP_IPC_LOCK  
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK  
NoNewPrivileges=yes  
ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl  
ExecReload=/bin/kill --signal HUP $MAINPID  
KillMode=process  
KillSignal=SIGINT  
Restart=on-failure  
RestartSec=5  
TimeoutStopSec=30  
LimitNOFILE=65536  
LimitMEMLOCK=infinity  
LimitCORE=0  
  
[nstall]  
WantedBy=multi-user.target  
```

```
$ sudo systemctl daemon-reload  
$ sudo systemctl start vault.service  
$ sudo systemctl status vault.service    

 vault.service - HashiCorp Vault - A tool for managing secrets  
   Loaded: loaded (/etc/systemd/system/vault.service; enabled; vendor preset: disabled)  
   Active: active (running) since Fri 2024-10-18 10:15:00 UTC; 5s ago  
     Docs: https://developer.hashicorp.com/vault/docs  
 Main PID: 1234 (vault)  
    Tasks: 8 (limit: 4915)  
   Memory: 5.6M  
   CGroup: /system.slice/vault.service  
           1234 /usr/bin/vault server -config=/etc/vault.d/vault.hcl  
  
Oct 18 10:15:00 your-hostname vault[234]: 2024-10-18T10:15:00.000Z [NFO]  core: unsealing vault  
Oct 18 10:15:00 your-hostname vault[234]: 2024-10-18T10:15:00.000Z [NFO]  seal: unseal process completed  
Oct 18 10:15:00 your-hostname vault[234]: 2024-10-18T10:15:00.000Z [NFO]  core: unseal complete  
Oct 18 10:15:00 your-hostname vault[234]: 2024-10-18T10:15:00.000Z [NFO]  proxy environment: http_proxy="" https_proxy="" no_proxy=""  
Oct 18 10:15:00 your-hostname vault[234]: 2024-10-18T10:15:00.000Z [NFO]  core: initializing storage  
Oct 18 10:15:00 your-hostname vault[234]: 2024-10-18T10:15:00.000Z [NFO]  core: loading configuration  
Oct 18 10:15:00 your-hostname vault[234]: 2024-10-18T10:15:00.000Z [NFO]  core: initializing listener  
Oct 18 10:15:00 your-hostname vault[234]: 2024-10-18T10:15:00.000Z [NFO]  core: initialized listener  
```

```  
$ vault operator init  
Unseal Key 1:  1a2b3c4d5e6f7g8h9i0j  
Unseal Key 2:  1j2k3l4m5n6o7p8q9r0s  
Unseal Key 3:  1t2u3v4w5x6y7z8a9b0c  
Unseal Key 4:  1d2e3f4g5h6i7j8k9l0m  
Unseal Key 5:  1n2o3p4q5r6s7t8u9v0w  
  
Initial Root Token: s.XYZ1234567890abcdef  
  
$ vault secrets enable transit  
Success! Enabled the transit secrets engine at: transit/  
  
$ vault write -f transit/keys/autounseal  
Success! Data written to: transit/keys/autounseal  
  
$ vault read transit/keys/autounseal  
Key              Value  
---              -----  
created_time     2024-10-18T10:00:00.000000000Z  
deletion_time    n/a  
destroyed        false  
exportable       false  
key_type         aes256-gcm96  
min_decryption_version 1  
name             autounseal  
```

```
$ sudo nano autounseal-policy.hcl    
# Define the policy for Auto Unseal in HashiCorp Vault  
  
# Allow the user to read and write to the transit secrets engine  
path "transit/keys/autounseal" {  
  capabilities = ["create", "read", "update", "delete", "list"]  
}  
  
# Allow the user to encrypt and decrypt data using the autounseal key  
path "transit/encrypt/autounseal" {  
  capabilities = ["create", "update"]  
}  
  
path "transit/decrypt/autounseal" {  
  capabilities = ["create", "update"]  
}  
  
# Allow the user to read the transit secrets engine configuration  
path "transit/\*" {  
  capabilities = ["read", "list"]  
}  
  
# Allow the user to list all keys under the transit secrets engine  
path "transit/keys/\*" {  
  capabilities = ["list"]  
}  
```

```
$ vault policy write autounseal-policy autounseal-policy.hcl  
Success! Added policy 'autounseal-policy'  
  
$ vault token create -policy=autounseal-policy    
Token:            s.1234567890abcdef  
Accessor:         12345678-1234-5678-1234-567812345678  
Policies:         [utounseal]  
Creation Time:    2024-10-18T10:00:00.000000000Z  
Policies:         [utounseal]  
Orphan:          false  
Lease Duration:   1h  
Renewable:       true  
```

## Overview of Primary Vault Operation:

*   **Install Vault**: Download and install Vault on the primary node.
*   **Configuration**: Create a configuration file for storage and listener settings.
*   **Service Management**: Set Vault to run as a system service using `systemd`.
*   **Initialization**: Initialize the Vault to generate unseal keys and a root token.
*   **Enable Transit Engine**: Activate the Transit Secrets Engine and create a key for auto-unseal.
*   **Create Policy**: Define a policy that grants permissions for the Transit engine.
*   **Generate Token**: Create a token that adheres to the policy for use by secondary Vault instances.

```
# Install Vault on the secondary server similarly to the primary server.  

$ sudo nano /etc/vault.d/vault.hcl    
listener "tcp" {  
  address     = "0.0.0.0:8200"  
  tls_disable = 1    
}  
  
# Configure the Raft storage backend  
storage "raft" {  
  path = "./vault/data"  # Change this to your desired data path  
}  
  
# Configure transit auto unseal  
seal "transit" {  
 address = "http://54.160.185.127:8200"  
token="hvs.CAESIJUVvaVhdrdR4l5CxZxpYNL5fpDLHdvm5gEXDFWSZzytGh4KHGh2cy5OMzl5TlNmNWR1TjNmVlNrY0YwWXhmcEY"  
 key_name = "autounseal"  
 mount_path = "transit/"  
}  
  
# Configure API and cluster addresses  
api_addr = "https://3.89.200.231:8200"  
cluster_addr = "https://3.89.200.231:8201"  
  
# Disable mlock for development; for production, this should be enabled  
disable_mlock = true  
  
# Enable the Vault web UI  
ui = true  
```

Now start serve

```
$ vault server -config=/etc/vault.d/vault.hcl    
==> Vault server configuration:  
  
   Administrative Namespace:   
             Api Address: http://<PUBLIC_IP>:8200  
                     Cgo: disabled  
         Cluster Address: https://<PUBLIC_IP>:8201  
   Environment Variables: HOME, LANG, LOGNAME, LS_COLORS, MAIL, PATH, SHELL, TERM, USER  
              Go Version: go1.22.7  
              Listener 1: tcp (addr: "0.0.0.0:8200", cluster address: "0.0.0.0:8201", disable_request_limiter: "false", max_request_duration: "1m30s", max_request_size: "33554432", tls: "disabled")  
               Log Level: info  
                   Mlock: supported: true, enabled: false  
           Recovery Mode: false  
                 Storage: file (HA available)  
                 Version: Vault v1.18.0, built 2024-10-08T09:12:52Z  
             Version Sha: 77f26ba561a4b6b1ccd5071b8624cefef7a72e84  
  
==> Vault server started! Log data will stream in below:  
  
2024-10-18T10:00:00.000Z [NFO]  proxy environment: http_proxy="" https_proxy="" no_proxy=""  
2024-10-18T10:00:00.000Z [NFO]  core: initializing storage  
2024-10-18T10:00:00.000Z [NFO]  core: loading configuration  
2024-10-18T10:00:00.001Z [NFO]  core: setting up seal  
2024-10-18T10:00:00.002Z [NFO]  core: unsealing vault  
2024-10-18T10:00:00.002Z [NFO]  seal.transit: attempting to unseal vault  
2024-10-18T10:00:00.003Z [EBUG] seal.transit: making encrypt request to transit secrets engine  
2024-10-18T10:00:00.004Z [NFO]  seal.transit: vault unsealed successfully  
2024-10-18T10:00:00.005Z [NFO]  core: unseal complete   
```

Check status

```  
$ vault status  
  
Seal Type:       transit  
Initialized:     true  
Sealed:          false  
Total Shares:    5  
Threshold:       3  
Version:         1.18.0  
Cluster Name:    vault-cluster-xxxxxxxx  
Cluster ID:      xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  
```

## Overview of Secondary Vault Operation:

**1. Installation and Configuration**:

*   The Vault server is installed on the secondary machine with similar configurations to the primary server. The `vault.hcl` file specifies,
*   **Storage Backend**: Uses file storage, which is not ideal for high availability but is simple for demonstration or smaller setups.
*   **Listener Configuration**: Sets up the listener to accept requests on all IP addresses at port 8200 without TLS.
*   **Seal Configuration**: Configures the seal mechanism to use the transit seal from the primary Vault server.

**2. Server Start**:

*   The command `vault server -config=/etc/vault.d/vault.hcl` is executed to start the Vault server.
*   The server initializes its storage and configuration, setting up the seal.

**3. Unsealing**:

*   The secondary Vault attempts to unseal itself using the transit seal mechanism.
*   It connects to the primary Vault to encrypt the unseal keys, enabling the secondary Vault to become operational without manual intervention.
*   The logs indicate that the unseal process is successful, confirming that it can access the primary Vault for auto-unsealing.

**4 Vault Status Check**:

The command `vault status` shows the following:

*   **Seal Type**: `transit`, indicating that it uses the transit seal method for unsealing.
*   **Initialized**: `true`, confirming that the Vault has been initialized, allowing it to function and manage secrets.
*   **Sealed**: `false`, meaning the Vault is operational and ready to accept requests.
*   **Total Shares**: `5` and **Threshold**: `3` show the unseal key shares configuration, which is used for manual unsealing if required in a different setup.
*   **Version**: `1.18.0` indicates the installed version of Vault.
*   **Cluster Name** and **Cluster ID** provide identifiers for the Vault cluster, suggesting that this server is part of a larger high-availability setup.

## Summary:

Incorporating HashiCorp Vaults transit auto-unseal mechanism enhances security and efficiency in secret management. By designating a primary Vault as a Key Management Service (KMS), organizations can automate the unsealing of secondary instances, minimizing manual intervention and associated risks  especially crucial in dynamic environments requiring high availability.

This blog explored various unsealing methods, including manual unseal with key shards for collaborative security and auto-unseal with AWS KMS for seamless integration into automated workflows. Each approach offers distinct advantages: manual unseal provides robust security, while auto-unseal emphasizes efficiency and resilience.

The transit auto-unseal mechanism exemplifies Vaults flexibility, allowing organizations to choose an unsealing strategy that aligns with their operational needs and security policies. By implementing strict access policies for the Transit Secrets Engine, we can ensure authorized actions and reinforce Vaults position as a reliable solution for secret management.

Ultimately, the choice between manual and auto-unseal methods depends on your specific use cases and risk tolerance. Whether prioritizing enhanced security or streamlined operations, HashiCorp Vault equips you with the necessary tools to meet your needs while maintaining high security standards.
