# Rive brief: Helmy, animated

One `.riv` file that the app drives. The app never plays a named animation; it
sets a few inputs, and the file's state machine chooses and blends. The same
file plays in the macOS splash window (Rive's Swift runtime, before Flutter
starts) and inside the app (the `rive` Flutter package).

Reference for every state: `faces/` (the head) and `poses/` (the full body).
The character is the rounder build in `poses/`.

## Art

The stills are flat images; animation needs parts. Redraw Helmy as vectors,
the soft vinyl look as gradients, in these separate layers:

- helmet shell, helmet rim, the two rivet dots
- left and right ear pieces
- the face (the glowing panel), each eye (open, closed, half; drawn so they
  can morph between), each brow, the mouth (smile, open, small frown, neutral)
- for the body: collar, torso with its button, upper and lower arms, hands
  (open, fist with thumb), legs, boots

Colors: cream body, black accents, the face a warm glow. The glow is one
shape whose brightness and warmth are driven by the `glow` input.

## Artboards

| Artboard | Shows | Used for |
|---|---|---|
| `head` | the head only, as the app icon | empty states, settings, small places |
| `tiny` | the head at 24-32 px, simplified (no rivets, thicker eyes) | the working indicator in a conversation |
| `body` | the full body | the splash window, onboarding, the site |

All three share one state machine, `Helmy`.

## Inputs

| Input | Type | Set by the app when |
|---|---|---|
| `isReady` | bool | startup is done |
| `isBusy` | bool | a message is being worked on |
| `isAnswering` | bool | text is streaming in |
| `needsYou` | bool | an approval or a question is waiting |
| `inBackground` | bool | background work is running |
| `isOffline` | bool | only the model on this Mac can answer |
| `done` | trigger | a turn ended well |
| `wentWrong` | trigger | a turn failed |
| `hello` | trigger | a new, empty session opens |
| `thumbsUp` | trigger | a friendly yes (a confirmation) |
| `glow` | number 0-1 | always: 0 dim, 0.5 steady, 1 bright |

## States

| State | Entered when | Motion |
|---|---|---|
| Dreaming | start; not `isReady` | eyes closed, slow breathing (about 3.2 s a breath), glow pulsing gently |
| Waking | `isReady` turns true | eyes open, head lifts off the hands, a small nod; plays once (about 1.2 s) |
| Idle | ready, nothing else | an occasional slow blink (every 4-7 s, varied), a faint sway |
| Thinking | `isBusy` and not `isAnswering` | eyes closed or looking up, hand to chin (body), glow brighter |
| Answering | `isAnswering` | eyes open, a small nod now and then, mouth opening a little |
| Needs you | `needsYou` | looks at the viewer, brows up, one hand raised (body) |
| Background | `inBackground` and nothing above | glances aside every few seconds |
| Done | `done` | happy closed arcs, a small nod or arms up (body); then Idle |
| Went wrong | `wentWrong` | a sorry tilt, palms up (body); then Idle |
| Offline | `isOffline` | sleepier eyes, glow dim and cool |
| Dozing | Idle for a long while (the file's own timer, about 5 min) | head droops, eyes closed; wakes on any input |
| Hello | `hello` | waves; then Idle |
| Thumbs up | `thumbsUp` | thumbs up with happy eyes; then Idle |

Priority when several are true: Needs you, then Answering, then Thinking, then
Background, then Offline, then Idle. Transitions blend over 0.2-0.4 s; nothing
snaps.

## Order of work

1. `head` and `body`: Dreaming, Waking, Idle (the splash needs these).
2. Thinking, Answering, Needs you (the busiest moments in the app).
3. The rest, one at a time. A new state is added in the file and wired to its
   input; nothing else changes.

## What the app does today

Until the file exists, the splash window shows the dreaming pose with a
breathing scale animation in Swift. Swapping in the `.riv` changes only what
draws the splash; the ready signal (`helmy/notify` `ready`) stays.
