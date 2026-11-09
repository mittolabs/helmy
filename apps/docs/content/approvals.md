---
title: Approvals
description: Helmy decides what agents may do, and asks you only what can't be undone.
---

People approve nearly every permission prompt they see, and stop reading them: Anthropic measured 93% approved in Claude Code. So Helmy doesn't show them. It decides.

## What happens to an action

1. **What only looks** (reading files, searching, fetching a page) goes ahead.
2. **Changes inside the chat's own folder** go ahead: Helmy snapshots the folder, so they can be undone.
3. **Commands that only read** (`ls`, `cat`, `git status`, `grep` and the like) go ahead.
4. **Everything else is judged** by a model that sees what you asked for and the action, and nothing else. It allows what serves your request, blocks what is unsafe or wasn't asked for, and asks you about what can't be undone.

A block goes back to the agent with the reason, so it can find a safer way. After three blocks in a row, or twenty in a chat, you're asked instead.

## What always comes to you

Whatever the judge thinks, these are put to you as a plain question:

- downloading a script and running it,
- `sudo`,
- reading passwords, keys or tokens (SSH, cloud credentials, the Keychain),
- anything that starts by itself at login, crontab, or shell startup files,
- changing an assistant's own settings, Helmy's included,
- and anything that leaves your Mac or can't be undone: sending, pushing, deploying, deleting outside the folder.

You answer **Go ahead** or **Don't**. Each step Helmy decided on its own says so, with its reason, when you open it.

## Prompt injection

Files, web pages and tool output can carry instructions meant for the agent. The judge never sees them: only your own messages and the action. Text inside an action that claims it is approved is treated as a reason to block it. And the fixed checks above apply whatever anything says.
