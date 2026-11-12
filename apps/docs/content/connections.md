---
title: Connections
description: Use Connections to give Helmy the AI tools it works through, and let it choose between them for you.
---

A connection is an AI tool Helmy works through. You add each one once; from then on you only talk to Helmy, which picks a connection for every message, so you get the most out of every subscription you pay for.

Connections appear only in **Settings > Connections**. In a chat, Helmy always answers as itself.

| Connection | Needs | Brings |
|---|---|---|
| OpenCode | No account | Free models, set up on first run |
| Claude Code | A Claude subscription | Work in your folders and connected accounts |
| Codex | A ChatGPT subscription | Work in your folders, and making and editing pictures |
| Cursor | A Cursor subscription | Work in your folders |
| Grok | A Grok account | Work in your folders |
| Antigravity | A Google account | Work in your folders |
| Ollama | No account | A model on your own computer, for working offline |

## Adding a Connection

1. Go to **Settings > Connections**.
2. Click **Add a connection**. Helmy lists what it found on your computer, and what it can install.
3. Choose one, and sign in if asked.

Helmy installs Cursor, Grok and Antigravity for you, and each signs in its own way: Cursor and Grok in a terminal or your browser, Antigravity with your Google account.

You can add a second Claude or ChatGPT account. Each has its own limits, and Helmy takes turns between them.

## How Helmy Chooses

For each message, Helmy:

1. Keeps the connections that can do what you asked. A picture needs one that makes images, for example.
2. Picks the one with the most of its limit left.
3. Sends quick questions to a free or local model where it can.

A conversation stays on its connection unless another has clearly more room. When a connection runs out, Helmy moves the conversation to another, with its history.

To see how much each connection has left, go to **Settings > Usage**. Cursor, Grok and Antigravity don't report their limits, so Helmy moves a conversation off one when it says it has run out.

## Adding Another Agent

Any agent that speaks the [Agent Client Protocol](https://agentclientprotocol.com), such as Gemini CLI, Goose or Kiro, can be a connection:

1. Go to **Settings > Connections** and click **Add a connection**.
2. Click **Another agent**, and choose one from the registry, or enter the command that starts it.

These answer only the kinds of work you set them best at, in **Settings > Connections > Advanced > Best at**, because Helmy can't see their limits or what they're good at.

## Turning a Connection Off

Open the connection in **Settings > Connections** and use its switch. Helmy stops sending it messages, and its sign-in stays. To take it out of the list, click **Remove from Helmy**.
