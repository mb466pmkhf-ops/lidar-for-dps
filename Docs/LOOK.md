# Look sheet

The rules every screen follows, on the iPhone and in the web/desktop planner. They exist so the app
reads as made for a film set, not as a generic template (see D-016 in `DECISIONS.md`).
`scripts/check-look.mjs` checks the mechanical ones in CI.

## Shape

- Two corner sizes only. Buttons, chips, fields, badges: **6** (`Theme.cornerSmall`, `var(--radius)`).
  Cards, panels, sheets, dialogs: **12** (`Theme.corner`, `var(--radius-lg)`). Circles stay circles.
- One button shape. Filled accent for the one main action on a screen, hairline for the rest,
  plain text for quiet actions. Day and night use the same shapes; only colours change.
- No pills, no frosted-glass blur, no coloured shadows or glows.
- Group with spacing and dividers first. A card is for something you can act on as a whole.

## Type

- Poppins for words, monospace for numbers that come from a meter or a tape (stops, lux, sizes).
- Labels in sentence case, no letter-spacing. No ALL-CAPS labels.
- The reading is the hero: on a panel about light, the stop is the biggest text.

## Colour

- One accent: blue `#1F5FD1` by day, dim teal `#4F9A8C` at night. Never yellow, amber or red as an accent.
- The false-colour stop scale (`stopColor` / `PlanLuxMap.color`) is the app's signature. Use those exact
  colours wherever a stop is shown, and nowhere else. The app icon and the desktop mark are made from it.
- Status dots only where the state needs attention (busy, synced, error). Signed-out is not an error.

## Words

- Say what the numbers are, not how to use the app. Gesture tips show once and can be dismissed.
- Longer explanations go behind a "What this means" disclosure.
- Provenance is a small glyph by the number (ruler measured, ± estimated, pencil by hand), with the
  word only where a section is labelled or explained.
- Sample content looks like a real job: real names, a real-sounding scene, no "Person 1" or "Demo".

## Home

- Home is your work first: rooms and projects as a list, newest first.
- The ways to start something new are plain buttons or rows above or below it, not a tile grid.
- Tools the device can't run are left out, with one line saying what this device supports.

## Getting around (iPhone)

- Home › project › room › plan. Each screen leads with the thing you came for: Home with your
  projects, a project with its rooms, a room with its plan.
- A room screen opens on the plan, with one big "Open the plan" button. Room size and what's placed
  are one small line under it, not a grid of big numbers. The plan screen does the same.
- Everything else is one list of rows (`ListRow` / `RowList`) that looks the same on every screen:
  icon, name, a short line, a count on the right, a chevron. No tile grids of tools.
- One door per place on a screen. On the room screen the plan is the preview and its button (no extra
  plan tiles or "Diagram" links further down); the 3D walkthrough is in the plan's options; export
  and the scout report are in the ••• menu.
- Capture tools the phone can't run are left out, as on Home. "Compare" appears once there are two
  rooms to compare.
- Something you set once (address, GPS, tags) sits under "Details", below the things you use daily.
