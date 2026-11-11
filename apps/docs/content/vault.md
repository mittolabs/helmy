---
title: The Vault
description: Use the Vault to give Helmy API keys and passwords that the AI uses by name and never sees.
---

The Vault keeps your secrets in your login Keychain, or your HashiCorp Vault, and hands them to commands as they run, so the AI can use a key without ever reading it.

<Info>
The Vault is available on macOS.
</Info>

Why it matters:

- **Keys never enter the conversation.** You type them into a private field, not the chat.
- **Output is blanked.** If a key appears in a command's output, Helmy replaces it with `[NAME]`.
- **Secret files are off limits.** The AI can't read `.env` files, key files or credential files. Example files such as `.env.example` stay readable.

## Adding a Key

When a task needs a key, Helmy asks for it in a private field in the chat:

1. Paste the key into the field.
2. Click **Save**.

You can also add keys in **Settings > Vault**.

## Moving Keys Out of .env Files

When a project keeps keys in `.env` files, Helmy offers once to move them into the Vault. Each line then names its key instead of holding it:

```bash
STRIPE_SECRET_KEY=vault:STRIPE_SECRET_KEY
```

Anything Helmy runs still gets the real value.

## Catching a Pasted Key

If you paste a key into a message, Helmy catches it before sending and offers to keep it in the Vault instead. It recognizes keys from Stripe, OpenAI, Anthropic, GitHub, AWS, Slack and others, and private keys.

## Using Keys in Your Terminal

Turn on `helmy run` in **Settings > Vault**. Then, in a project's folder:

```bash
helmy run npm run dev
```

The command runs with the project's keys and the shared ones. Helmy needs to be open.

## Connecting HashiCorp Vault

1. Go to **Settings > Vault** and connect with its address and a token. For Enterprise or HCP, add a namespace.
2. Add a key **From HashiCorp Vault**, with its path and field.

Helmy fetches the value only when something runs, and never keeps a copy.
