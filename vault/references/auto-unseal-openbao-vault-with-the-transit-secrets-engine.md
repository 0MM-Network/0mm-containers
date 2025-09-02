# [Auto Unseal OpenBao/Vault with the Transit Secrets Engine](https://labs.iximiuz.com/tutorials/openbao-vault-auto-unseal-transit-82d2a212 "Auto Unseal OpenBao/Vault with the Transit Secrets Engine")

Tutorial by [Márk Sági-Kazár](https://sagikazarmark.com/ "Márk Sági-Kazár")

### Table of contents

*   [Preparations](#preparations)
*   [How it works](#how-it-works)
*   [Configuring the unsealer](#configuring-the-unsealer)
*   [Configuring the service](#configuring-the-service)
*   [Manual sealing](#manual-sealing)
*   [Summary](#summary)
*   [What's next?](#whats-next)
*   [References](#references)

In this tutorial, you'll learn how to unseal [OpenBao](https://openbao.org/) and [Vault](https://developer.hashicorp.com/vault) automatically using the **Transit secrets engine**.

You'll walk through how to:

*   Set up the Transit secrets engine
*   Enable automatic unsealing using the Transit seal

💡 To dive deeper into the concepts covered in this tutorial, check out the [References](https://labs.iximiuz.com/tutorials/openbao-vault-auto-unseal-transit-82d2a212#references) section.

## Preparations

First, choose whether to use **OpenBao** or **Vault**. The included playground has both pre-installed.

Enter one of the following values:

*   `openbao`
*   `vault`

Choose the service you want to use throughout the tutorial.

Start playground to activate this check

Waiting for the service to start...

Start playground to activate this check

Waiting for the unsealer to start...

Start playground to activate this check

## How it works

Automatic unsealing isn't fundamentally different from the manual unsealing process.

In the manual process, a set of **unseal keys** is required to reconstruct the **root key** (or _master key_). The root key is then used to decrypt the **encryption key**, which the service uses to access the underlying data.

💡 To learn more about the unsealing process, check out [this tutorial](https://labs.iximiuz.com/tutorials/openbao-vault-getting-started-e783c133).

With automatic unsealing, an external service manages the encryption of the root key, eliminating the need for unseal keys.

![Auto unseal process](Auto%20Unseal%20OpenBao_Vault%20with%20the%20Transit%20Secrets%20Engine_files/auto-unseal-process-v5.svg)

The service is configured for automatic unsealing via the `seal` stanza.

Both OpenBao and Vault support several unsealing mechanisms, including:

*   Cloud KMS (AWS, GCP, Azure, etc.)
*   PKCS#11 (HSM)
*   Transit secrets engine (built-in "KMS")

- - -

In this tutorial, you'll use the **Transit secrets engine** for simplicity, though the setup is similar to other supported unsealing mechanisms.

You'll configure two instances of OpenBao/Vault:

*   An unsealer (with the Transit secrets engine enabled) running in **dev mode**
*   A standard installation of the service, configured for automatic unsealing

## Configuring the unsealer

Since the unsealer runs in dev mode, you don't need to configure a storage backend or initialize it.

However, you'll still need to enable the Transit secrets engine so it can be used to unseal other instances.

To enable the secrets engine, switch to the unsealer and run the following command:

OpenBao

Vault

`bao secrets enable transit`

Copy to clipboard

`vault secrets enable transit`

Copy to clipboard

Waiting for the Transit secrets engine to be enabled...

Start playground to activate this check

You'll also need to create a key in the new secrets engine for the unsealer to use when encrypting and decrypting the root key:

OpenBao

Vault

`bao write -f transit/keys/unseal-key`

Copy to clipboard

`vault write -f transit/keys/unseal-key`

Copy to clipboard

Waiting for `unseal-key` to be written to the store...

Start playground to activate this check

## Configuring the service

The service that will be automatically unsealed is already configured to use the in-memory storage backend.

Switch to the playground and configure the unsealing process:

OpenBao

Vault

/etc/openbao/config.d/seal.hcl

`seal "transit" {   address = "http://unsealer:8200"  token   = "iximiuz"   key_name   = "unseal-key"  mount_path = "transit/" }`

Copy to clipboard

Hint 1 💡

`sudo -u openbao $EDITOR /etc/openbao/config.d/seal.hcl`

Copy to clipboard

Configuration breakdown

*   The [`seal` stanza](https://openbao.org/docs/configuration/seal) sets up the [Transit seal](https://openbao.org/docs/configuration/seal/transit).
*   `address` and `token` specify the connection details for the instance configured as the unsealer service.
*   `key_name` and `mount_path` define the location of the transit key used to encrypt and decrypt the root key.

Then restart the service:

`sudo systemctl restart openbao`

Copy to clipboard

/etc/vault.d/config.d/seal.hcl

`seal "transit" {   address = "http://unsealer:8200"  token   = "iximiuz"   key_name   = "unseal-key"  mount_path = "transit/" }`

Copy to clipboard

Hint 1 💡

`sudo -u vault $EDITOR /etc/vault.d/config.d/seal.hcl`

Copy to clipboard

Configuration breakdown

*   The [`seal` stanza](https://developer.hashicorp.com/vault/docs/configuration/seal) sets up the [Transit seal](https://developer.hashicorp.com/vault/docs/configuration/seal/transit).
*   `address` and `token` specify the connection details for the instance configured as the unsealer service.
*   `key_name` and `mount_path` define the location of the transit key used to encrypt and decrypt the root key.

Then restart the service:

`sudo systemctl restart vault`

Copy to clipboard

Waiting for the Transit seal to be configured...

Start playground to activate this check

As with any new instance, you'll need to **initialize** the service, but this time, the process will be slightly different.

In a typical initialization, a set of unseal keys is generated and used to reconstruct the root key during the unsealing process.

With auto unsealing enabled, unseal keys are no longer needed, since an external service manages the encryption of the root key. Instead, a set of **recovery keys** is created.

This is because the service can still be manually sealed, even with auto unsealing enabled (for example, as a protective measure to restrict access). In such cases, recovery keys are used to manually unseal the service.

It's important to note that recovery keys are **not** related to the root key. They serve purely as an authorization mechanism, ensuring that only those who possess them can unseal a manually sealed service.

The external service that manages root key encryption is still required to complete the unsealing process.

To initialize the service, use the following command:

OpenBao

Vault

`bao operator init -recovery-shares=1 -recovery-threshold=1`

Copy to clipboard

`vault operator init -recovery-shares=1 -recovery-threshold=1`

Copy to clipboard

⚠️ Similarly to key shares and threshold, using `-recovery-shares=1 -recovery-threshold=1` in production is **not recommended**, as it creates a single recovery key with no redundancy. This configuration is used here for simplicity.

Waiting for the service to be initialized...

Start playground to activate this check

Make sure to save both the **recovery key** and the **root token**.

Once the initialization is complete, the service should be unsealed automatically.

Waiting for the service to be unsealed...

Start playground to activate this check

## Manual sealing

Let's test the manual sealing process.

Log in to the service using the root token received during initialization:

OpenBao

Vault

`bao login`

Copy to clipboard

`vault login`

Copy to clipboard

Waiting for login to complete...

Start playground to activate this check

Seal the service:

OpenBao

Vault

`bao operator seal`

Copy to clipboard

`vault operator seal`

Copy to clipboard

Waiting for the service to be sealed...

Start playground to activate this check

You can verify the seal status by looking at the result of the status command:

OpenBao

Vault

`bao status`

Copy to clipboard

`vault status`

Copy to clipboard

Now, unseal the service using the recovery token received during initialization:

OpenBao

Vault

`bao operator unseal`

Copy to clipboard

`vault operator unseal`

Copy to clipboard

Waiting for the service to be unsealed...

Start playground to activate this check

## Summary

**🎉 Congratulations!**

You’ve learned how automatic unsealing works in OpenBao/Vault.

While this tutorial used the Transit secrets engine, the same concepts apply to other supported unsealing mechanisms. For more details, check out the [References](https://labs.iximiuz.com/tutorials/openbao-vault-auto-unseal-transit-82d2a212#references) section below.

## What's next?

There's still plenty more to explore:

*   See the [References](https://labs.iximiuz.com/tutorials/openbao-vault-auto-unseal-transit-82d2a212#references) section below to dive deeper into the topics covered
*   Check out additional tutorials and challenges to expand your knowledge

If you want to test your knowledge or experiment further, check out these playgrounds:

*   [OpenBao](https://labs.iximiuz.com/playgrounds/openbao-3ff3b736)
*   [Vault](https://labs.iximiuz.com/playgrounds/hashicorp-vault-2076021e)
*   [OpenBao vs Vault](https://labs.iximiuz.com/playgrounds/openbao-vault-b46f1fb6)

## References

💡 To dive deeper into the concepts covered in this tutorial, check out the resources below.

OpenBao

Vault

*   [Auto unseal](https://openbao.org/docs/concepts/seal/#auto-unseal)
*   [Transit secrets engine](https://openbao.org/docs/secrets/transit)
*   Configuration
    *   [`seal` stanza](https://openbao.org/docs/configuration/seal)
    *   [Transit](https://openbao.org/docs/configuration/seal/transit)

*   [Auto unseal](https://developer.hashicorp.com/vault/docs/concepts/seal/#auto-unseal)
*   [Transit secrets engine](https://developer.hashicorp.com/vault/docs/secrets/transit)
*   Configuration
    *   [`seal` stanza](https://developer.hashicorp.com/vault/docs/configuration/seal)
    *   [Transit](https://developer.hashicorp.com/vault/docs/configuration/seal/transit)

html .default .shiki span {color: var(--shiki-default);background: var(--shiki-default-bg);font-style: var(--shiki-default-font-style);font-weight: var(--shiki-default-font-weight);text-decoration: var(--shiki-default-text-decoration);}html .shiki span {color: var(--shiki-default);background: var(--shiki-default-bg);font-style: var(--shiki-default-font-style);font-weight: var(--shiki-default-font-weight);text-decoration: var(--shiki-default-text-decoration);}

Level up your Server Side game — Join 12,000 engineers who receive insightful learning materials straight to their inbox

Subscribe

Experiment right in your browser

![Web terminal](Auto%20Unseal%20OpenBao_Vault%20with%20the%20Transit%20Secrets%20Engine_files/webterm.png) [Start tutorial](https://labs.iximiuz.com/signup?return_to=%2Ftutorials%2Fopenbao-vault-auto-unseal-transit-82d2a212)

✕

### How to Author Tutorials on iximiuz Labs

Instead of providing a subpar online editing experience, iximiuz Labs offers a helper CLI tool called [labctl](https://github.com/iximiuz/labctl), allowing you to use your favorite text editor (or a full-featured IDE) to write content from the comfort of your local machine.

#### Install labctl CLI

`curl -sf https://labs.iximiuz.com/cli/install.sh | sh`

This will download and install the latest version of the labctl CLI. You only need to do this once per workstation.

#### Authorize labctl

`labctl auth login`

This will open a browser window asking you to authorize labctl to access your account. You need to do it after a fresh install of labctl and repeat it whenever the auth session expires.

#### Pull tutorial content

`labctl content pull tutorial openbao-vault-auto-unseal-transit-82d2a212`

This will create a local copy of the tutorial content in a directory named `openbao-vault-auto-unseal-transit-82d2a212`. You only need to do this once per tutorial.

#### Stream your changes

`labctl content push -fw tutorial openbao-vault-auto-unseal-transit-82d2a212`

Run this command in a separate terminal to continuously upload your changes to the server while editing the tutorial in your favorite text editor or IDE.

You can also use labctl to create, list, and delete your content. Learn more about the available commands: `labctl content --help`

