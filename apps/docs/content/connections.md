---
title: Connections
description: Learn which AI tools Helmy works through, how it chooses between them, and how to add your own.
---

A connection is an AI tool Helmy does its work through. You add a connection once. After that, you only talk to Helmy: in a chat, it's always Helmy that answers. Connections only appear in **Settings**, under **Connections**, and how much each has left under **Usage**.

| Connection | Account | What it brings |
|---|---|---|
| OpenCode | None needed | Free models, set up for you on first run |
| Claude Code | A Claude subscription | Works in your folders and your connected accounts |
| Codex | A ChatGPT subscription | Works in your folders, and makes and edits pictures |
| Ollama | None needed | A model on your own computer, for when you're offline |

## Add a connection

1. Open **Settings**, then **Connections**.
2. Choose **Add a connection**. Helmy lists what it found on your computer, and what it can install.
3. Choose one, and sign in if it asks.

You can add a second Claude or ChatGPT account. Each has its own usage limits, and Helmy takes turns between them.

## How Helmy chooses

For each message, Helmy:

1. keeps the connections that can do what you asked (pictures, for example, need one that makes images);
2. picks the one with the most of its usage limit left;
3. answers quick questions with a free or local model where it can.

A conversation stays on its connection unless another has clearly more room, since each switch hands the conversation across. When a connection runs out, Helmy moves the conversation to another, history and all, and you don't need to do anything.

## Turn one off

Open a connection in **Settings** and use its switch. When it's off, Helmy sends it nothing, but its sign-in and its place in the list stay. **Remove from Helmy** takes it out of the list instead.
