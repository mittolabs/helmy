# AGENTS.md

<!-- ashlar: written by ashlar init and apply, and written again by them; keep notes of your own outside these lines -->
## Ashlar UI

This app's interface is built from Ashlar UI components, copied into `lib/ui/core/ashlar`: they are the
app's own code, to read and change.

- **Build from the components in `lib/ui/core/ashlar`**, not Material or Cupertino widgets: Button,
  Input, Card, Dialog and the rest. `ashlar search <words>` finds one, with whole
  screens (blocks) among them; `ashlar view <name>` shows its source; `ashlar add <name>`
  copies it in with what it needs.
- **Take colours, text and corners from the theme**, never a colour written in the code:
  `final t = AshlarTheme.of(context);` then `t.colors.primary`, `t.colors.mutedForeground`,
  `t.text.sm`, `t.radiusMd`. The app's theme is `lib/ui/core/ashlar/app_theme.dart`.
- **Every control is a Pressable**, for hover, press, keyboard focus and a screen
  reader's label; an icon alone needs a `semanticLabel`.
- **Icons are ashlaricons**: `AshlarIcon(AshlarIconsRoundedStroke.plus)`.
- **Start and end, not left and right** (`EdgeInsetsDirectional`, `AlignmentDirectional`),
  so the app reads right to left too.
- **Look at what you built**: `ashlar shot lib/screens/home.dart --size phone,desktop --both`
  draws a screen to `.ashlar/shots/` without running the app and names any overflow with
  its line; read the pictures. A screen that needs providers or a route is drawn from a
  harness under `test/` that wraps it in them. `ashlar check` reports contrast and
  accessibility faults.
- **Each component's tests are in `test/ashlar`**; run `flutter test` after changing one.
- `ashlar mcp` serves search, view, add, update, check and shot over MCP.
<!-- ashlar: end -->
