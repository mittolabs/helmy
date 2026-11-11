# Helmy's artwork

The master images for Helmy, the mascot. Made 2026-11-04 with Codex's image
generation, each edited from the one before so the character stays the same:
an original cream vinyl robot in a helmet, with black ear pieces and rivets and
a warm glowing face. It is based on no film, TV, game or toy character.

- `icon/light.png`, `icon/dark.png`: the app icon's head, on white and on black.
  On black, the app's copies have their ear pieces lifted to a dark gray, so
  they still read at small sizes (the app icon's `head-dark.png`, and each
  Dock face's dark version).
- `faces/`: the head in each state the app shows (dreaming while loading,
  waking when ready, thinking, answering, needs you, working in the background,
  done, went wrong, offline, dozing).
- `poses/`: the full-body mascot in the same states, plus hello (a new, empty
  session) and thumbs up (a friendly yes). This rounder build is the mascot.

The glow is part of the character: bright and warm while working, steady when
ready, dim when resting, dim and cool when offline (on the model on this Mac).

Where the app shows them, as stills for now:

- the Dock: the face for what Helmy is doing (waking up just after it opens,
  thinking, answering, needs you, in the background, done, went wrong,
  offline, dozing), drawn exactly where the app icon's head sits;
- the sidebar title: the head;
- a new, empty session: hello, or offline when only this Mac can answer;
- a "Finished" notification: thumbs up;
- the splash: dreaming.

These are stills for judging the look. The animated Helmy is built from them
in Rive: one file, a state machine the app drives with a few inputs.

## The site's waving Helmy (2026-11-11)

`poses/hello-wave/` holds three frames edited from `poses/11-hello.png` by the same
pipeline as the poses (Codex image generation, with the prompt beside them): the hand
tilted out, the hand tilted in, and a blink. The site plays them over each other with
short crossfades (`apps/site/web/styles.css`, `.wave`): two waves, then a blink through a
soft oval over the eyes only, so nothing else moves. Each frame was cut from its white
background by a flood fill from the edges, with the white taken back out of the edge
pixels, cropped to one shared square and saved as WebP (`apps/site/web/helmy/hello-*.webp`).

A hand-drawn vector Helmy was tried first and dropped: off-model (Mittolabs
`docs/notes/helmy.md`).
