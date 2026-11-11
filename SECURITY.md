# Security

## Report a problem privately

Please don't open a public issue for a security problem. Report it privately on GitHub instead:

1. Open [Report a vulnerability](https://github.com/mittolabs/helmy/security/advisories/new).
2. Say what the problem is, how to make it happen, and what someone could do with it.

Only the people who look after Helmy can see your report. We'll reply there, and credit you when it's fixed, unless you'd rather we didn't.

## Which versions

Fixes go into the latest release. Please check that the problem is still there in it.

## What's in scope

Helmy runs AI tools on your computer, so these matter most:

- an action that runs without the approval it should have needed;
- a secret from the vault reaching a conversation, a log or a connection;
- instructions in a file, web page or tool output getting past Helmy's checks;
- the phone link: anyone without the pairing code reading or sending anything;
- anything in Helmy's own updates, downloads or helmy.ke.

A problem in Claude Code, Codex, OpenCode or Ollama themselves belongs with their makers.
