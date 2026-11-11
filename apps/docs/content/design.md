---
title: Design
description: Learn how to ask Helmy for screens and pages, and change them on the canvas.
---

Ask Helmy for an app's screens, a landing page, a mockup or a poster, and it lays them out on a canvas in the **Design** tab beside the chat. They're real pages, not pictures, and nothing is published unless you ask.

## Ask for a design

Say what you want, and give Helmy what it needs to know:

*Make a landing page for Rise Bakery. Everything I know is in notes.md. Keep it warm and simple, with a way to pre-order weekend loaves.*

The canvas opens beside the chat, and redraws as Helmy works.

## Move around

- **Scroll** with two fingers to move.
- **Zoom** with a pinch, or ⌘ plus and minus.
- **Fit everything** by pressing the zoom percentage.

## Edit on the canvas

1. Press **V** to select. Click an element, drag it to move it, or drag its handles to resize it.
2. Double-click text to change it. **Enter** keeps the change, **Esc** drops it.
3. Use the arrow keys to nudge, with **Shift** for 10 pixels. **Delete** removes. **Undo** is in the toolbar.

Your edits are saved into the design's files, so Helmy sees them.

## Ask for a change

1. Press **C** to comment.
2. Click the element you mean, and say what should change.

Your comment joins your next message, naming the screen and the element, so Helmy knows exactly what you're pointing at.

## Check every size

Each screen is drawn in its device: a phone, a tablet or a browser window. Hover a responsive page to see it at a phone's, a tablet's or a desktop's width.

## Where the files are

A design is a `design` folder in the chat's folder: one HTML file per screen, and `canvas.json`, which places each one.

```json
{
  "title": "Bloom",
  "boards": {
    "welcome.html": { "x": 0, "y": 0, "w": 390, "h": 844, "title": "Welcome" }
  },
  "order": ["welcome.html"]
}
```

## Next steps

- Learn [how to hold a design on your phone](/phone).
