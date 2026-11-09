---
title: Design
description: Screens on a canvas, made while you talk.
---

Ask Helmy for an app's screens, a mockup, a landing page or a poster, and it lays them out on a canvas in the **Design** tab beside the chat.

## On the canvas

- **Move around:** scroll with two fingers, pinch or press ⌘ plus and minus to zoom, and press the percentage to fit everything.
- **Select and edit (V):** click an element to select it, drag it to move it, and drag its handles to resize it. Double-click text to retype it; Enter keeps it, Esc lets it go. The arrow keys nudge (Shift for 10 pixels), Delete removes, and Undo is in the toolbar.
- **Comment (C):** click an element and say what should change. The comment joins your next message, naming the screen and the element.
- **Devices:** draws each screen in its device: a phone, a tablet or a browser window.
- **Responsive pages:** hover one to see it at a phone's, a tablet's or a desktop's width.

Your edits are saved into the design's files, so the agent sees them.

## The files

A design is a `design` folder in the chat's folder: `canvas.json`, which places each screen, and one HTML page per screen. Agents write them with their own file tools.

```json
{
  "title": "Bloom",
  "boards": {
    "welcome.html": { "x": 0, "y": 0, "w": 390, "h": 844, "title": "Welcome" }
  },
  "order": ["welcome.html"],
  "notes": { "onboarding": { "x": 0, "y": -200, "text": "Onboarding", "kind": "title" } }
}
```

## On your phone

A chat with a design shows **See the design** on your paired phone. See [Your phone](/phone).
