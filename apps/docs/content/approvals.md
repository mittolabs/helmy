---
title: Approvals
description: Use Approvals to let Helmy handle routine steps on its own, and ask you only about what can't be undone.
---

Most AI tools ask permission for nearly every step, and people end up approving almost all of it unread. Helmy decides routine steps itself, against what you asked for, so you're only asked about the ones that matter.

Why it matters:

- **Fewer prompts.** Reading, searching, and changing files in the chat's folder go ahead without asking.
- **A clear question when it counts.** Anything that can't be undone comes to you, in plain words.
- **A reason for every decision.** Click any step to see what Helmy decided, and why.

## What Helmy Does on Its Own

- Reading files, searching, and fetching pages.
- Changing files in the chat's folder. Helmy keeps a snapshot, so these can be undone.
- Commands that only read, such as listing a folder or checking a repository's status.

Everything else is checked against your request. Helmy allows what serves it, stops what's unsafe or wasn't asked for, and asks you about what can't be undone. A stopped step goes back to the AI with the reason, so it can find a safer way. After three stops in a row, Helmy asks you instead.

## What Always Comes to You

- Downloading a script and running it.
- Running something as an administrator.
- Reading passwords, keys or tokens.
- Setting up something that starts on its own, or changing how your shell starts.
- Changing an assistant's own settings, Helmy's included, or running a script an assistant installed.
- Acting on one of your connected accounts, such as creating a site.
- Anything that leaves your computer or can't be undone: sending, pushing, deploying, or deleting outside the chat's folder.

Click **Go ahead** or **Don't**.

<Info>
Files, web pages and tool output can carry instructions meant to trick an AI. Helmy's check only sees your own messages and the action itself, so instructions hidden in that content can't talk their way past it.
</Info>

Learn more about [keeping keys out of the chat](/vault).
