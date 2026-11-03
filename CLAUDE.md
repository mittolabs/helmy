# CLAUDE.md

Helmy: dream it, do it. A desktop app you talk to, that gets things done in
your folders and accounts.

In the Mittolabs workspace its product page is `docs/products/helmy.md` and its
working notes `docs/notes/helmy.md`. Decision `0008` is why it is Dart and
Flutter, and `0012` why its UI is Ashlar UI.

## The rule everything follows

**Helmy is the assistant. Nothing else is.** Claude Code, Codex and models on
Ollama are connections: the means Helmy uses to get things done, added in
Settings the way you add an account. After that they never show.

- In a conversation, Helmy never names them, never says it is one of them, and
  never passes on their wording: their errors, their notices, their quirks.
  Talking to Helmy should feel like talking to a model of its own.
- Which connection answers a message is Helmy's choice, made per message
  (capability, then measured headroom, then the model on this Mac), and is
  never shown.
- Settings is the one place they appear, as connections to add, check and
  turn off.

When a change would let one of them show through, it is a bug.

## Layout

One repository, per the workspace's `docs/engineering/repos.md`:

- `apps/app/`: the Flutter app, macOS first, in the house architecture
  (`docs/engineering/flutter.md`): view models with `Command` and `Result`,
  repositories over services, `provider` and `go_router`. Its
  `lib/ui/core/ashlar/` is Ashlar UI, copied in by the `ashlar` command: a fix
  that is Ashlar's goes to `ashlar-ui/registry/` and is copied again; a look
  that is Helmy's own stays in Helmy's copy.
- `Makefile`: every command, run from the root.

Only create a folder the product actually has.

## Toolchain

- Flutter through fvm on stable (`apps/app/.fvmrc`): `fvm flutter`, `fvm dart`.
  Never a global SDK.
- `make setup` installs the commit hook and dependencies.
- Live tests (`make live`) drive the real CLIs and cost real usage; unit tests
  (`make test`) never do.

## Commits

Conventional Commits, per `docs/engineering/commits.md`; the hook in
`.githooks/` refuses a malformed subject. No co-author or "generated with"
lines.
