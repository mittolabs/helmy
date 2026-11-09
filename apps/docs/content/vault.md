---
title: The vault
description: Secrets the agent uses by name and never sees.
---

API keys, passwords and tokens live in Helmy's vault: in your Mac's login Keychain, or in your HashiCorp Vault. Agents get their **names**, never their values.

## How agents use them

- `vault_list` gives the names a chat can use: its project's, and the shared ones.
- `vault_run` runs a command with the secrets as environment variables. Whatever it prints comes back with every value replaced by `[NAME]`.
- `vault_ask` asks you for a missing secret through a private field in the chat. It never goes into the conversation.

Agents can't read `.env` files, key files or credential files at all; Helmy's approvals block it. Example files such as `.env.example` stay readable.

## .env files

When a project has secrets in its `.env` files, Helmy offers once to move them into the vault. Each line then names its secret instead of holding it:

```bash
STRIPE_SECRET_KEY=vault:STRIPE_SECRET_KEY
```

Frameworks that load `.env` leave a variable that is already set alone, so anything run through Helmy, or `helmy run`, gets the real value.

## Pasted by mistake

A key pasted into a message (Stripe, OpenAI, Anthropic, GitHub, AWS, Slack and others, or a private key) is caught before it is sent. Helmy offers to keep it and sends `vault:NAME` in its place.

## In your terminal

Settings, Vault sets up `helmy run`. In a project's folder:

```bash
helmy run npm run dev
```

runs the command with that project's secrets and the shared ones. Helmy has to be open.

## HashiCorp Vault

Connect it in Settings, Vault with its address, a token and, for Enterprise or HCP, a namespace. Then add a secret **From HashiCorp Vault** with its path and field. Helmy fetches the value only when something runs, and never keeps a copy.
