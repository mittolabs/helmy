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
- Settings (and the first-run onboarding) are the only places they appear,
  as connections to add, check and remove.

When a change would let one of them show through, it is a bug.

## Two principles every change is judged by

**Helmy chooses for the user.** Opinionated, intent-based design: the user
says what they want, and Helmy decides how (which connection, which model,
how much effort, how many opinions), well and efficiently. Complexity is
carried by Helmy, not handed over (Tesler's law). No model pickers, effort
dials or knobs that only exist because we did not decide. A setting earns its
place only when people genuinely differ in what they want.

**When something goes wrong, Helmy shows the cause and the fix.** Never a
vague failure, never "go to Settings to find out". Every problem says what
happened and why in plain words, where it happened, with one action that
fixes it there: sign in, allow a permission (opening the exact system pane),
start what stopped, try again. An error Helmy cannot explain still says what
happened, with the details a press away and a way to report it. (Nielsen's
ninth heuristic: recognize, diagnose, recover.) Explaining a problem in
Helmy's words is not hiding it.

## When Helmy gets a tool of its own

Helmy's own tools (served to every connection over its MCP server) are only
for what a connection's agent cannot do itself, because it needs something
only Helmy has:

- **Helmy's permissions**: Accessibility, Screen Recording, the Photos
  library, anything the agent's sandbox is kept from.
- **Helmy's links**: the paired phone, the Preview panel's browser, the
  Device panel.
- **Helmy's native reach**: Apple frameworks that are impractical from a
  shell (Vision, Core Audio, ScreenCaptureKit).

What the agent can already do with a command (convert a file, resize a
picture, read the battery) is not a tool. When doing it is painful, fix the
pain where it is instead: harmless commands that ask for approval, a
connection's quirk showing through, a result left in a connection's folder,
an agent asking for what it could have looked up. Decide from the turn log
(how often chats hit it), not from one chat.

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

`main` is protected (a ruleset, since 2026-11-11): no pushing to it, no force
push, no deleting it. Every change goes through a pull request, and merges once
the app check (`test`) passes. Work on a branch, `gh pr create`, and merge
when it is green. Rewriting history (as when the repository went public) means
lifting the ruleset for that moment, on purpose.
