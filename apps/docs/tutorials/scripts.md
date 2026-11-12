# Tutorial scripts

Six short tutorials for Helmy's docs, one per page, recorded in the real app and voiced by
Mitto (ElevenLabs). Written in the docs' voice (`../STYLE.md`, Spoken Scripts): Sentry's grammar, with the
warmth carried by Mitto's delivery, not by the words.

Voiced with `eleven_v4`, the newer Mitto clone (`fKtBZdKg49gqg92XX3Dh`), stability 0.6,
similarity 0.95, style 0.15, and no delivery cues: chosen by ear on 2026-11-11 as the one
that sounds like Mitto. Cues pulled the voice away from it.

Recorded in the sample folder `~/Studio` (fictional names, US places, dollars), on a
fresh Helmy, with only Helmy's window captured.

---

## 1. Getting Started

**Install Helmy, set up a connection, and send your first message.**

| On screen | Mitto |
|---|---|
| helmy.ke, the download page | This tutorial shows you how to install Helmy and send your first message. It takes about two minutes. |
| The macOS card, downloading | Go to helmy dot k e, slash download, and download the build for your computer. |
| The disk image: drag Helmy onto Applications | Open it, and drag Helmy into Applications. |
| macOS blocks it; System Settings > Privacy & Security > Open Anyway | This build isn't signed yet, so macOS blocks it the first time. Go to System Settings, then Privacy and Security, and click Open Anyway. You only need to do this once. |
| Setup: Connections | On first run, Helmy walks you through setup, starting with Connections: the AI tools Helmy works through. |
| The free connection, on | Helmy sets up a free connection that needs no account, so you can start right away. |
| A found subscription, switched on by hand; Cursor, Grok and Antigravity rows | If you have a Claude or ChatGPT subscription, Helmy finds it and leaves it off until you switch it on, so it never spends a subscription you didn't choose. Cursor, Grok and Antigravity are one click away. |
| Chats step, then Folders | Next, bring in your existing chats if you want them, and choose where new chats start. |
| The message box; typing "What's in my Studio folder?"; Enter | Type what you want done, and press Enter. |
| The answer arriving | Helmy picks a connection for the message, does the work, and answers. There's no model to choose. |
| The answer, settled | Next, learn how to run your first task. |

---

## 2. Your First Task

**Give Helmy a real task in a folder, and follow the work as it happens.**

| On screen | Mitto |
|---|---|
| A new chat; Finder beside it: a messy Downloads folder | This tutorial shows you how to give Helmy a real task: tidying a folder. |
| Typing the request | Describe the outcome and what matters to you. Here, Helmy sorts the folder and keeps the newest copy of any duplicate. |
| Helmy's first line; the steps appearing | Helmy says what it's about to do, then does it. |
| A step line, opened | Each line under the reply groups a set of steps. Click one to see exactly what ran. |
| The approval card | Moving files within the folder can be undone, so Helmy goes ahead. Removing files can't, so Helmy stops and asks. |
| Clicking Go ahead | Click Go ahead, or Don't. |
| The summary: what moved, what was set aside, the log | When Helmy finishes, it summarizes what moved and what it set aside, and keeps a log of every change. |
| Finder: the tidy folders | The folder is now sorted. |
| The chat's row, its one-line status | Each chat keeps a one-line status in the sidebar, so you can pick up where you left off. Next, learn what Helmy asks you about. |

---

## 3. Approvals

**Let Helmy handle routine steps on its own, and ask you only about what can't be undone.**

| On screen | Mitto |
|---|---|
| A chat mid-task, steps passing with no prompts | Most AI tools ask permission for nearly every step. Helmy decides routine steps itself, so you're only asked about the ones that matter. |
| Steps reading files, checking status | Reading files, searching and fetching pages go ahead without asking. |
| Steps editing files in the chat's folder | Changes in the chat's folder go ahead too. Helmy keeps a snapshot, so you can undo them. |
| A step opened, its reason shown | Everything else is checked against what you asked for. Click any step to see what Helmy decided, and why. |
| The approval card | Anything that can't be undone comes to you as one plain question: deleting, sending, publishing, or using a password. |
| Clicking Don't; Helmy finding another way | If you click Don't, Helmy looks for another way, or asks what you'd prefer. |
| The docs page, Approvals | Next, learn how the Vault keeps your keys out of the chat. |

---

## 4. The Vault

**Give Helmy API keys and passwords that the AI uses by name and never sees.**

| On screen | Mitto |
|---|---|
| A chat in a sample project that needs a Stripe test key | This tutorial shows you how to give Helmy an API key without it ever entering the chat. |
| Helmy asking: the private field in the chat | When a task needs a key, Helmy asks for it in a private field. The key goes to your Mac's Keychain, not into the conversation. |
| Pasting, keeping it | Paste the key, and click Keep it. |
| Helmy running the command; the output shows [STRIPE_SECRET_KEY] | Helmy now runs what needs the key, and only ever sees its name. If the key appears in the output, Helmy blanks it out. |
| A key pasted into the message box by mistake; Helmy catching it | If you paste a key into a message by mistake, Helmy catches it before it's sent, and offers to keep it in the Vault. |
| Terminal: helmy run npm run dev | To use the same keys in your own terminal, run your command with helmy run. |
| Settings > Vault | Your keys are listed in Settings, under Vault. Next, learn how to design with Helmy. |

---

## 5. Design

**Get screens and pages by asking for them, then change them by hand or by comment.**

| On screen | Mitto |
|---|---|
| A new chat; typing a request for a bakery's landing page | This tutorial shows you how to get a landing page by asking for one, here for a small bakery. |
| The Design tab opening, the page drawing in | Helmy lays the page out on the Design canvas, beside the chat. These are real pages, not pictures. |
| Zooming and moving around | Scroll to move around the canvas, and pinch to zoom. |
| Double-clicking the heading, retyping it | Double-click any text to change it. Your edits are saved into the page, so Helmy sees them. |
| Comment tool: clicking the order button, "make this stand out more" | To ask for a change, press C and comment on the element you mean, so Helmy knows exactly what you're pointing at. |
| The button updating on the canvas | The canvas updates as Helmy works. |
| The page at phone, tablet and desktop widths | Hover a page to see it at phone, tablet and desktop widths. Next, learn how to follow your chats on your phone. |

---

## 6. Your Phone

**Pair your phone with Helmy to follow, approve and stop work from anywhere.**

| On screen | Mitto |
|---|---|
| Settings > Phone, the switch on, the code showing | This tutorial shows you how to pair your phone with Helmy. On your computer, go to Settings, then Phone, and turn on Reach Helmy from your phone. |
| Phone: Scan the code; paired | Open Helmy on your phone, tap Scan the code, and scan the code your computer shows. |
| Phone: the chat list, live | Your chats now appear on your phone, live, with anything waiting on you at the top. |
| Phone: opening the waiting chat, tapping Go ahead | Open a chat to approve a step, send a message, or stop a task, from wherever you are. |
| The computer: the same chat carrying on | The work stays on your computer. Your phone follows it, and sends it your instructions. |
| Settings > Phone, paired phones | Each paired phone is listed in Settings, under Phone, where you can unpair it. |
