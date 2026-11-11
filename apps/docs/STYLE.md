# How Helmy's docs are written

Modeled on Sentry's docs (docs.sentry.io, read 2026-11-11): minimalist, technically
exact, and centered on what the reader is trying to get done.

## The voice

- **The product is the subject, in the present tense.** "Helmy picks a connection for each
  message", not "Helmy will pick" or "you can have Helmy pick".
- **Feature names are proper nouns.** Chats, Connections, Usage, Approvals, the Vault, the
  Design canvas, the Browser panel. Capitalized wherever they name the feature.
- **Say what it is, then what it lets you do: "so you can …".**
- **Concrete over abstract.** Name the file, the setting, the example.
- **Second person, plain words, short sentences.** US English. No em dashes (a colon,
  a comma or parentheses instead).

## A page

1. **Title:** the feature's name, Title Case.
2. **Description** (the line under the title): an imperative that names the benefit.
   "Use Approvals to decide what Helmy does on its own, and what it asks you first."
3. **First paragraph:** what it is, and what it lets you do.
4. **Why It Matters:** three to five bullets, each a bold label and its payoff.
5. **Examples:** when you'd use it, as concrete cases.
6. **Task sections:** Title Case, often a gerund ("Adding a Connection"), with numbered
   steps. Setup uses "Step 1:".
7. **Navigation as a path:** **Settings > Connections**.
8. **Learn more:** a link to the page that goes deeper, inline, at the end of a section.

## Leave out

- What the interface already makes obvious.
- Anything not critical to getting started, on a primary page: it goes to a subpage.
- Claims nobody has checked against the app. When a feature is on one system only, say
  which.
