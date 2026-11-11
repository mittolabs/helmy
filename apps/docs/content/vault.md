---
title: The vault
description: Learn how to give Helmy API keys and passwords without them ever entering the chat.
---

The vault keeps your API keys, passwords and tokens where the AI can use them by name, but never see them.

<Info>
The vault is on macOS for now, where it keeps your secrets in your login Keychain or your HashiCorp Vault.
</Info>

## Add a key

You don't need to set anything up first. When a task needs a key, Helmy asks for it in a private field in the chat.

1. Paste the key into the field.
2. Choose **Save**.

The key goes to your Keychain, not into the conversation. You can also add keys yourself in **Settings**, under **Vault**.

## How Helmy uses keys

When Helmy runs something that needs a key, the key is passed to it directly. If the key shows up in the output, Helmy blanks it out as `[NAME]`, so the AI only ever sees its name.

The AI can't read `.env` files, key files or credential files at all. Example files, such as `.env.example`, stay readable.

## Move keys out of .env files

When a project keeps keys in its `.env` files, Helmy offers once to move them into the vault. Each line then names its key instead of holding it:

```bash
STRIPE_SECRET_KEY=vault:STRIPE_SECRET_KEY
```

Anything Helmy runs gets the real value.

## Pasted a key by mistake?

If you paste a key into a message, Helmy catches it before it's sent, and offers to keep it in the vault instead. It recognizes keys from Stripe, OpenAI, Anthropic, GitHub, AWS, Slack and others, and private keys.

## Use your keys in a terminal

Turn on `helmy run` in **Settings**, under **Vault**. Then, in a project's folder:

```bash
helmy run npm run dev
```

This runs the command with the project's keys, and the shared ones. Helmy needs to be open.

## Use HashiCorp Vault

1. Open **Settings**, then **Vault**, and connect it with its address and a token. For Enterprise or HCP, add a namespace.
2. Add a key **From HashiCorp Vault**, with its path and field.

Helmy fetches the value only when something runs, and never keeps a copy.

## Next steps

- Learn [what Helmy asks you about](/approvals).
