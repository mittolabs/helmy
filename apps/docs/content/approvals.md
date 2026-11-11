---
title: Approvals
description: Learn what Helmy does on its own, what it asks you first, and why.
---

Most AI tools ask permission for almost every step, and people end up approving nearly all of it without reading: in one study, 93% of permission prompts were approved. Helmy decides most of these itself, and only asks you about what matters.

## What Helmy just does

1. **Looking:** reading files, searching, and fetching a page.
2. **Changing files in the chat's folder.** Helmy keeps a snapshot, so these can be undone.
3. **Commands that only read,** such as listing a folder or checking a repository's status.

## What Helmy checks

Everything else is checked against what you asked for. Helmy allows what serves your request, stops what's unsafe or wasn't asked for, and asks you about what can't be undone. When Helmy stops a step, the AI is told why, so it can find a safer way. If it gets stopped three times in a row, Helmy asks you instead.

To see what Helmy decided, open a step in the chat. Each step it decided on its own shows its reason.

## What always comes to you

Whatever the check thinks, these are always put to you as a plain question:

- downloading a script and running it;
- running something as an administrator;
- reading passwords, keys or tokens;
- setting up something that starts by itself, or changing how your shell starts;
- changing an assistant's own settings, Helmy's included, or running a script an assistant installed;
- acting on one of your connected accounts, such as creating a site;
- anything that leaves your computer or can't be undone: sending, pushing, deploying, or deleting outside the chat's folder.

Answer **Go ahead** or **Don't**.

<Info>
Files, web pages and tool output can contain instructions meant to trick an AI. Helmy's check only ever sees your own messages and the action itself, never that content, so hidden instructions can't talk their way past it.
</Info>

## Next steps

- Learn [how Helmy keeps your keys out of the chat](/vault).
