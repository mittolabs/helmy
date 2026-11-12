---
title: Design
description: Use the Design canvas to get screens and pages by asking for them, then change them by hand or by comment.
---

<Tutorial src="design" title="Design, in about a minute" />

Ask for an app's screens, a landing page, a mockup or a poster, and Helmy lays them out on the Design canvas beside the chat. They're real HTML pages, not pictures, so you can resize them, edit their text, and point at exactly what to change. Nothing is published unless you ask.

Some examples of what to ask for:

- *Make a landing page for Rise Bakery, from notes.md, with a way to pre-order weekend loaves.*
- *Design the onboarding screens for a habit tracker app.*
- *Lay out a poster for a Saturday farmers market.*

## Editing on the Canvas

- **Move around:** scroll with two fingers, pinch or press ⌘ plus and minus to zoom, and click the zoom percentage to fit everything.
- **Select (V):** click an element, drag to move it, or drag its handles to resize it.
- **Edit text:** double-click it. **Enter** keeps the change, **Esc** drops it.
- **Nudge:** the arrow keys, with **Shift** for 10 pixels. **Delete** removes.

Your edits are saved into the design's files, so Helmy sees them.

## Asking for a Change

1. Press **C** to comment.
2. Click the element you mean, and say what should change.

The comment joins your next message, naming the screen and the element, so Helmy knows exactly what you're pointing at.

## Checking Every Size

Each screen is drawn in its device: a phone, a tablet or a browser window. Hover a responsive page to see it at phone, tablet and desktop widths.

## Where the Files Are

A design is a `design` folder in the chat's folder: one HTML file per screen, and a `canvas.json` that places them.

```json
{
  "title": "Bloom",
  "boards": {
    "welcome.html": { "x": 0, "y": 0, "w": 390, "h": 844, "title": "Welcome" }
  },
  "order": ["welcome.html"]
}
```

Learn more about [holding a design on your phone](/phone).
