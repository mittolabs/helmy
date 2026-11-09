---
title: Connections
description: The AI tools Helmy works through, and how it chooses between them.
---

A connection is an AI tool Helmy does its work through. Helmy names them only in **Settings, Connections and usage**; in a chat, it is always Helmy that answers.

| Connection | What it brings |
|---|---|
| Claude Code | Works in your folders and connected accounts |
| Codex | Works in your folders, and makes and changes pictures |
| OpenCode | Free models with no account, for quick questions |
| Ollama | A model on this Mac, for when nothing online can answer |

You can add another Claude Code or Codex account, each with its own usage limits; Helmy moves to one as another runs low.

## How Helmy chooses

For each message, Helmy picks a connection that can do what is asked, then the one with the most of its limit left. A thread stays on its connection unless another has clearly more room, since each switch hands the conversation across. **Best at** in Settings lets you say which kind of connection takes which kind of work.

## Turning one off

Each connection has a switch in its details. Off, it gets no messages, and nothing else changes: its sign-in, its install and its place in the list stay. **Remove from Helmy** takes it out of the list instead.
