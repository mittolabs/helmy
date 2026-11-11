# Tutorial scripts

Six short tutorials for Helmy's docs, one per page, each recorded in the real app and
voiced by Mitto (ElevenLabs, `eleven_v4`). Each has a one-line promise, what you see on
screen, and what Mitto says. Only the "Mitto" lines are voiced.

Recorded in the sample folder `~/Studio` (fictional names, US places, dollars), on a
fresh Helmy, with only Helmy's window captured.

---

## 1. Getting started

**Learn how to install Helmy, connect it, and send your first message.** About 1 min 15 s of voice; the video runs longer where Helmy works.

| On screen | Mitto |
|---|---|
| helmy.ke/download, the macOS card | In this tutorial, you'll install Helmy and send your first message. Start at helmy dot k e, slash download, and get the build for your Mac. |
| Finder: unzip, drag Helmy to Applications | Unzip it, and drag Helmy into your Applications folder. |
| macOS blocks the first open; System Settings, Privacy & Security, Open Anyway | This first build isn't signed yet, so macOS stops it the first time. Open System Settings, then Privacy and Security, and choose Open Anyway. You only do this once. |
| Onboarding, Connections step | Helmy opens with a short setup. First, connections. These are the AI tools Helmy works through. |
| The free connection, on | You don't need an account to start. Helmy sets up a free connection for you. |
| A found subscription, switched on by hand | If you already pay for Claude or ChatGPT, Helmy finds them on your Mac. They stay off until you switch them on, so Helmy never spends a subscription you didn't choose. |
| Chats step, then Folders step | Next, you can bring in chats you had in those tools, and choose where new chats start. |
| The empty chat, the message box | That's it. Type what you want done, the way you'd ask a person. |
| Typing: "What's in my Studio folder?" and sending | Press Enter to send. |
| Helmy's answer arriving | Helmy picks the right connection for the message, does the work, and answers. You never choose a model. |
| The answer, settled | Next, learn how to give Helmy a real task. |

---

## 2. Your first task

**Learn how to give Helmy a task in a folder, and follow what it does.** About 55 s of voice.

| On screen | Mitto |
|---|---|
| A new chat, ~/Studio/Downloads in Finder beside it: a mess of files | In this tutorial, you'll ask Helmy to tidy a downloads folder. |
| Typing the request: sort it into folders, keep the newest of any duplicates | Say what you want, and what matters to you. Here: sort it into folders, and keep the newest copy of anything duplicated. |
| Helmy's first line, the steps appearing | Helmy says what it's going to do, then does it. |
| A step row, opened | Each line like this is a group of steps. Open one to see exactly what ran. |
| The approval card: move three older copies to the Trash? | Moving files around in this folder can be undone, so Helmy just does it. Removing files is different, so it asks first. |
| Pressing Go ahead | Press Go ahead, or Don't. |
| The summary: what moved, what went to the Trash, the cleanup log | When it's done, you get a short summary: what moved, what went to the Trash, and a log of every change. |
| Finder: the tidy folders | And the folder, sorted. |
| The chat in the sidebar, its one-line status | Every chat keeps a one-line note of where it stands, so you can come back later. Next, learn what Helmy asks you about, and what it doesn't. |

---

## 3. Approvals

**Learn what Helmy does on its own, and what it asks you first.** About 50 s of voice.

| On screen | Mitto |
|---|---|
| A chat mid-task, steps passing with no prompts | In this tutorial, you'll see how Helmy decides what needs your approval. |
| Steps that read files, run `git status` | Most of what an AI tool does is looking: reading files, searching, checking. Helmy lets that through. |
| Steps editing files in the chat's folder | Changes inside the chat's own folder go ahead too. Helmy keeps a snapshot, so you can undo them. |
| A step opened, its reason shown | Everything else is checked against what you asked for. Open any step to see what Helmy decided, and why. |
| The approval card | Anything that can't be undone comes to you as one plain question: deleting outside the folder, sending, pushing, or using a password. |
| Pressing Don't; Helmy finding another way | If you say Don't, Helmy finds another way, or asks you what you'd like instead. |
| The docs page, Approvals | That's it. You stop clicking Allow on every step, and only answer the questions that matter. Next, learn how Helmy handles your keys. |

---

## 4. The vault

**Learn how to give Helmy a key without it ever entering the chat.** About 50 s of voice.

| On screen | Mitto |
|---|---|
| A chat in a sample project needing a Stripe test key | In this tutorial, you'll give Helmy an API key, safely. |
| Helmy asking for the key: a private field in the chat | When a task needs a key, Helmy asks for it in a private field like this one. What you type goes to your Mac's Keychain, not into the conversation. |
| Pasting into the field, saving | Paste it here, and save. |
| Helmy running the command; the output shows [STRIPE_SECRET_KEY] | Helmy can now run things that need the key. It only ever sees its name. If the value turns up in the output, it's blanked out. |
| A key pasted into the message box by mistake; Helmy catching it | And if you paste a key into a message by mistake, Helmy catches it before it's sent, and offers to keep it in the vault instead. |
| Terminal: `helmy run npm run dev` | You can use the same keys in your own terminal, with helmy run. |
| Settings, Vault | Your keys are listed in Settings, under Vault. Next, learn how to design screens by asking for them. |

---

## 5. Design

**Learn how to ask for screens, and change them on the canvas.** About 45 s of voice.

| On screen | Mitto |
|---|---|
| A new chat; typing a request for a bakery's landing page from its notes | In this tutorial, you'll ask Helmy to design a landing page. |
| The Design tab opening beside the chat, the page drawing in | Helmy lays the page out on a canvas, right beside the chat. These are real pages, not pictures. |
| Zooming and moving around the canvas | Scroll to move around, and pinch to zoom. |
| Double-clicking the heading, retyping it | Double-click any text to change it. Your edits go straight into the files, so Helmy sees them. |
| Comment tool: clicking the order button, typing "make this stand out more" | To ask for a change, comment on the part you mean. Your comment joins your next message, so Helmy knows exactly what you're pointing at. |
| Sending; the button updating on the canvas | Send it, and the canvas updates as Helmy works. |
| The responsive page at phone, tablet and desktop widths | Hover a page to see it at a phone's, a tablet's, or a desktop's width. Next, learn how to take Helmy with you. |

---

## 6. Your phone

**Learn how to pair your phone, and keep up with your chats away from your Mac.** About 45 s of voice.

| On screen | Mitto |
|---|---|
| Mac: Settings, Phone, the switch on, the code showing | In this tutorial, you'll pair your phone with Helmy. On your computer, open Settings, then Phone, and switch on Reach Helmy from your phone. |
| Phone: Helmy, Scan the code; the phone paired | Open Helmy on your phone, and scan the code. That's the whole setup. |
| Phone: the chat list, live | Your chats are here now, live. Anything that needs you is at the top. |
| Phone: opening the waiting chat, pressing Go ahead | Open it to answer, send a message, or stop a task, from wherever you are. |
| Mac: the same chat carrying on | The work stays on your computer. Your phone shows it, and tells it what to do. |
| Phone: Your Mac | On a Mac, you can even see its screen, and use it, from your phone. |
| Settings, Phone, paired phones | Every paired phone is listed in Settings, where you can remove it. That's everything you need to get started with Helmy. |
