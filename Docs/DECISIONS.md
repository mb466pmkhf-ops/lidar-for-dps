# Decisions

Short log of product and technical decisions. Newest last. "Open" items need the product owner.

## D-001 · Working name FrameScan, code stays FrameScout — 2026-10-20 · open
The product is now called FrameScan. The Xcode project, target, bundle id (`com.framescout.app`), display
name and Swift types still say FrameScout. Renaming touches signing and the user's existing installs
(new bundle id = new app, data not carried over), so it is deferred until the owner confirms the final name.
Changing only `CFBundleDisplayName` is a cheap, safe first step when ready.

## D-002 · Every figure carries a provenance — 2026-10-20
`Provenance` (measured / estimated / manual) lives in `Core/Models/Provenance.swift`.
- Measured: RoomPlan walls/openings and polygon floor area, mesh ceiling (classified triangles), LiDAR AR tape, plan measurements.
- Estimated: RoomPlan ceiling (RoomPlan doesn't detect ceilings, we use the tallest wall), mesh room size
  (bounding box), bounding-box floor area, completeness, compass north, AR measure on non-LiDAR devices (plane raycasts).
- Manual: typed measurements, north calibrated by hand.
UI shows a badge with icon + word (not colour alone); PDF uses ≈ / ✎ markers; CSV has a `provenance` column;
`measurements.json` gains optional `provenanceOverride`.

## D-003 · Build on the latest branch — 2026-10-20 · superseded 2026-11-10
New work used to branch from `claude/dreamy-archimedes-lo0whf` because the default branch was behind. PR #11
brought the default branch `claude/framescout-ios-app-pbswdo` up to date, so new work branches from the
default branch again. Renaming it to `main` is still the owner's call.

## D-004 · Docs folder is `Docs/`
The repository already uses `Docs/`. `Docs/ARCHITECTURE.md` serves as the technical guide.

## D-005 · Original look everywhere except Home — 2026-10-21
After comparing three versions in the Simulator, the owner kept the original site style (Poppins light, wide
tracking, square hairline frames, white as the only accent) for every screen except Home. Home uses its own
`HomeStyle` (Features/Home/HomeStyle.swift): Poppins at readable weights with Dynamic Type, a teal accent,
rounded icon tiles that say why a tool is unavailable, and more spacing. No yellow accents. Bug fixes from the
practical pass stay app-wide: plan labels avoid marks and stay on screen, Sun time chips scroll, the provenance
badge sits under the value.

## D-006 · Lighting previs: a stated photometric model, never viewport brightness — 2026-10-29
Lux, stops and power draw come only from `Core/Models/Photometrics.swift`, `Exposure.swift` and
`LightingCalculator.swift`. The 3D viewport's brightness is a visual guide and is compressed on purpose.
- Fixtures are generic types (COB, fresnel, panel, mat, tube, HMI, tungsten, lantern, bulb), no brands. Each
  has a reference reading (lux on axis at a distance, in its reference configuration), beam shape, colour
  range and an emitter size. All library figures are **estimated**; a user's own reading per unit
  (`photometricOverride`) is **manual**. Wattage is a label and a draw estimate, never an output.
- Model: peak intensity from the reference, total flux conserved through modifiers (which change the beam
  shape) and scaled by filters (gels, ND, diffusion). Inverse square with an extended-source term for discs
  and an exact line-source term for tubes, cosine incidence, and the summed contributions of every unit.
  Barn doors cut each side of the beam with a soft 6° edge — a simplification, labelled as such.
- Occlusion: walls block, windows pass the "light through glass" value (default 78 %), closed doors block,
  flags/negs block, diffusion frames pass 50 %. Bounce boards re-emit once (80 % reflectance). Room
  inter-reflections and colour of surfaces are **not** modelled, so real interiors read brighter than the
  estimate, especially with soft sources. Everything shown is badged "estimated".
- Exposure: incident-meter equation N²/t = E·S/C with C = 250, set in T-stops (T includes lens loss); the
  f-stop is shown as T × √transmission for reference. ND in stops. Key lux follows ISO, shutter, T-stop and ND.
- Hiding a unit changes only the view; switching it off changes the light.
- 2026-11-10 audit: formulas re-derived and tested by hand; library figures checked against published
  maker tables and raised where they were a stop or more low (tungsten fresnels, COBs); a fresnel now
  loses flux when spotted (flux ∝ (beam ÷ flood)^0.85, fitted to studio fresnel tables) instead of keeping
  it; an HMI that can't dim to a target says so. CI compares every fixture configuration and exposure
  between Swift and TypeScript (`web/tests/photometry-audit.test.ts`). Not modelled: tubes radiate all
  round their axis (many real tubes are one-sided), and panels are fully diffuse (some have a ~50° lens).
- Scan alignment is a stored correction (`ScanRecord.alignment`), applied to the whole 3D world (scan, cameras,
  lights, people) so positions stay consistent; the scan files and the 2D plan are not changed.

## D-007 · Web and desktop planner, synced through Supabase — 2026-11-05
The owner asked for a web app and a desktop app that continue the lighting plan from the iPhone, fully
synced. Recommended on a decision card; built on this default while the owner confirms.
- **Planner**: `web/` (React + TypeScript, Vite). The lighting maths is a line-for-line port of
  `Photometrics.swift`, `LightingCalculator.swift` and `Exposure.swift`; CI runs the Swift calculator over a
  web-written project (`web/tests/fixtures/parity-bundle.json`) and fails if any reading differs (> 1e-6
  relative), which also proves the phone decodes web edits. The web edits project.json as raw JSON and
  only touches fields it knows, so keys from newer iOS builds survive.
- **Desktop**: the same web app in a Tauri 2 window (`web/src-tauri`), built by CI for macOS (universal dmg)
  and Windows (msi/exe). Chosen over Mac Catalyst because the iOS app depends on ARKit/RoomPlan and Windows
  users are covered too. Builds are unsigned.
- **Sync transport**: Supabase (Postgres + Auth), owner's own free project, email + password accounts. Plain
  REST from every client (URLSession on iOS), so no third-party SDK. CloudKit was the alternative but needs
  the paid Apple Developer Program and an Apple ID on the web. Confirmed by the owner 2026-11-06; project
  `framescan` (`nuprvuipspqmhsczdqrk`, eu-west-2) is built in as the default server on every client, and
  nothing uploads until the user signs in.
- **What uploads**: `project.json` and each scan's `plan.json` (walls, openings, set pieces) — only after the
  user turns sync on and signs in. Scan meshes, textures, USDZ and photos never leave the phone. Rows are
  protected by row-level security (owner = signed-in user); setup SQL in `web/supabase/schema.sql`.
- **Conflicts**: compare-and-swap on a per-project revision. When two devices edited the same project, a
  three-way merge against the last-synced copy keeps both sides' changes item by item (lights, people,
  meters, shots…); a field changed on both sides keeps the device that is saving. `SyncMerge.swift` and
  `web/src/sync/merge.ts` implement the same rules and share test cases.
- Polling every 5 s (web) / 10 s (phone) while open; no realtime socket yet.

## D-008 · "Big buttons, daylight" look, with a night mode — 2026-11-10
The owner compared three mockups (guided steps, big buttons in daylight, plan first) and picked the second,
then asked for it to be built with a night switch for dark sets. This replaces D-005's dark hairline look.
- **Day (default)**: light page (#F3F4F1), white cards, near-black text, one blue accent (#1F5FD1), Poppins at
  regular/medium weights, rounded controls at least 44 px tall. No yellow or amber accent.
- **Night**: near-black page, dimmed warm-grey text and a dim green-teal accent, so the screen puts as little light
  as possible into a dark set. A switch in the top bar; remembered per device.
- **Home**: a few big labelled tiles (continue, draw a room, open a file, sync), then recent locations.
- **Draw a room**: a starting shape (box or L) plus typed sizes becomes the same `FloorPlan` a scan makes
  (`web/src/model/room.ts`), stored as a scan named "Drawn by hand" so the plan, 3D view and lighting maths
  work unchanged. Typed sizes are never presented as measured.
- The 2D plan stays simple, but cameras and units are drawn as recognisable equipment (body, lens, matte box,
  softbox, barn doors, stand legs). The 3D viewport keeps its dark studio backdrop in both modes.

## D-009 · Security baseline — 2026-11-10
From a whole-app audit (security, bugs, performance).
- **Sync server**: the anon key in the apps is public by design; access control is row-level security.
  `framescan_projects` is keyed by (owner, id), so one account can't block another by taking a project id.
  Signed-out requests have no table privileges at all; signed-in users get select/insert/update/delete only.
  Rows are capped (doc 5 MB, plans 20 MB) so one account can't fill the database.
- **Tokens**: on the phone the session is in the Keychain, this device only (not in backups). On web and
  desktop it is in localStorage, protected by a strict Content Security Policy (scripts from the app only,
  network to HTTPS only). A refresh token the server rejects signs the user out instead of retrying.
- **Imported files**: backups and synced documents are untrusted. ZIP entries and photo file names can't
  point outside the project folder, and the ZIP reader rejects truncated or oversized entries.
- **Builds**: npm and Cargo lockfiles are committed; third-party GitHub Actions are pinned to a commit.
  Desktop installers are unsigned (macOS will warn on first open) until the owner has signing certificates.


## D-010 · Sign in with Apple, Google or email — 2026-11-11
Owner asked for Google and Apple sign-in, a password confirmation and email verification, on the
phone and the desktop.
- **One flow everywhere**: Apple and Google go through Supabase's web sign-in with PKCE, not the native
  Sign in with Apple capability, because the owner signs with a free Personal Team (no capabilities).
  Apple still needs the paid Developer Program on the server side (Services ID + key). Setup steps:
  `Docs/SIGN_IN_SETUP.md`.
- **Desktop**: providers block embedded web views, so the Tauri app opens the system browser and catches
  the redirect once on a fixed loopback port (127.0.0.1:53682–53684, listed in Supabase). No new crates.
- **Email accounts**: password typed twice, at least 8 characters; the address is confirmed by link or by
  the code in the email before the account gets a session.
- **Findable on the phone**: Home has a *Sign in to sync* card and a person icon; it was only in the ⋯ menu.

## D-011 · What the 3D picture is allowed to claim — 2026-11-11
The 3D view was rebuilt for picture quality (HDR, soft shadows, contact shading, glow, modelled equipment,
furniture and people). Better pictures look more trustworthy, so the rules of D-006 are restated for it.
- **From the photometric model**: each unit's colour, its brightness relative to the other units, and (web and
  desktop) its falloff across the beam and its barn-door cut, which are the calculator's own curves projected by
  the light. Shadow softness follows the size of the source.
- **Not modelled, and said so on screen**: light bouncing round the room, daylight (added in D-014), and bounce boards. The
  picture shows direct light plus a trace of work light so the room stays readable.
- **Brightness**: by default the picture is fitted to the screen (the brightest reading sits a little over
  mid-grey). Web and desktop can instead show it at the set stop, where an incident reading equal to the key
  puts a mid-grey card at mid-grey. Either way it is labelled a preview; readings stay the figures to use.
- **Stand-ins**: furniture, floorboards, wall paint and clothing are neutral stand-ins sized to the scan. The
  scan knows shapes and sizes, not finishes. Equipment stays generic (no maker's designs).
- **Speed**: the web view draws only when something changes and drops contact shading, then glow, then
  resolution if the machine can't keep up.
- The iPhone has the same picture pipeline but still draws the room from the scan's own geometry; the modelled
  room, furniture and projected beam pattern are web and desktop only for now.

## D-012 · Changing the set by hand, and plans that merge — 2026-11-11

Doors, windows, openings and furniture can be added, moved, resized, turned and deleted on the plan, on the
iPhone and on web/desktop (`SetPieces.swift` ↔ `web/src/model/setPieces.ts`, same presets and rules).

- **Presets, not measurements**: pieces start at typical sizes from a short list. Anything placed or changed
  by hand carries `byHand: true` (an optional field, so older plans load) and is labelled "Entered by hand"
  with a dashed outline on the plan. Scanned pieces stay "from the scan" until someone changes them.
- **Snapping**: a door or window goes in the wall nearest the tap (within 1 m), stays inside the wall's ends and
  under its top, and slides along or onto another wall when dragged. Furniture dropped near a wall turns to back
  onto it. Set pieces move only once selected, so dragging across a furnished room still pans the plan.
- **Sync**: plans now merge three ways like project.json (doors, windows and pieces by id) on both sides, and
  the phone uploads its plans whenever they changed, not only when a scan was added. Before this, the phone
  never took a plan it already had and the web let the server's plan win, so edits could be lost.
- **3D on the iPhone**: a room built from the plan is rebuilt; a real scan keeps its own geometry, with hand-placed
  pieces drawn over it as simple boxes and scanned pieces that were moved or deleted hidden.
- Not done: moving or adding walls, and changing the ceiling height after a room is drawn.

## D-013 · Grip as a second source, and a steady 3D brightness — 2026-11-12
Vorbi found that moving a person in front of a neg made every unit in the 3D view brighter, that a diffusion
frame didn't diffuse, and that grip didn't behave like the real thing.
- **Optics per board** (`BoardOptics` / `boardOptics`): transmission, scatter (share of what gets through that is
  diffused) and reflectance. Defaults: bounce board 0.8 reflectance; flag 0.04 and neg 0.03 (black cloth); full
  diffusion passes 0.5, all of it scattered, and throws 0.35 back. These are general figures, not a maker's
  data; drapes from the grip catalogue can override them.
- **How it is modelled**: each board is split into 3 × 3 patches. Light landing on a patch (with everything
  else in the way) is re-emitted as a small matte source: off the lit face for what is reflected, out of the
  far face for what a diffusion scatters. A direct ray through a board keeps only transmission × (1 − scatter).
  One bounce only; boards don't light each other. Same maths in Swift and TypeScript, tested on both.
- **3D picture**: flags and negs cut the beam (every unit up to six casts shadows), show a faint sheen on the
  lit side, and the beam haze stops at them. A diffusion stops the hard beam, glows where it is lit, and lights
  the far side as a soft source. Bounce boards light their side the same way. Still no light off walls or
  daylight (until D-014), and the on-screen note says so (amends D-011).
- **Brightness fit**: "fitted to the screen" now follows the strongest unit at full output, 3 m off. It used to
  follow the brightest reading, so moving a person or a flag re-exposed the whole picture. Moving people or
  grip, or dimming a unit, no longer changes how bright the other units look.
- Readings far below T1 (over six stops under) now read "under T0.13", not "T0".

## D-014 · Studio sets, daylight and curtains — 2026-11-12

A location can be dressed as a studio and lit by the sun and sky through its windows, on the iPhone
("Daylight and studio set…" in the plan menu, curtain picker on a selected window) and on web/desktop (Overview
and window panels). Maths in `Stage.swift` ↔ `web/src/model/stage.ts`, checked against each other in CI.

- **Backdrops** (generic names only): white, black, green, blue and painted cyc; white, grey, black and colour
  paper rolls; an LED wall. They go on a wall (the one the camera faces by default, else the longest) with a
  width, height and position along it. Floors: grey, black or painted concrete, white painted floor.
- **Only the LED wall counts as light.** It is an area source at the brightness set in nits, worked out with the
  exact Lambert formula for a lit rectangle, blocked by walls. Backdrop and floor colours change the picture
  only; their reflectance is shown as a figure, but nothing bounces, so it is not added to readings.
- **Daylight is a standard sky, not the location's weather**: IES daylight-availability model (clear, hazy,
  overcast), Kasten-Young air mass, twilight to 6° below the horizon. The sun is placed by hand or from the
  date, time, coordinates and the scan's north; without coordinates or north the app says so and stays by hand.
- Sun reaches a point only along a ray through a window that no wall blocks; sky light comes in as an area
  source per window, with the window seeing half sky, half sunlit ground (20 % reflectance). Nothing outside
  (trees, buildings, overhangs) is known, so real figures are often lower. All daylight figures are **estimated**.
- **Curtains**: sheer passes half the light and stops the sun's hard beam (it glows instead); blackout passes none.
- **3D picture**: sky behind the windows, a sun light that only enters through openings (an invisible ceiling
  casts shadow), sheer curtains glowing, backdrops and floors in their colours. Intensities are clamped so the
  frame stays readable; viewport brightness is still not a reading.
- The iPhone draws the set with SceneKit (simpler cove, gradient sky, area light for the LED wall); it was
  built in CI but not checked on a device.

## D-016 · A written look sheet, checked in CI — 2026-11-12

Vorbi asked whether the app looked "vibecoded" and then to fix what the review found: identical
rounded tiles as the main UI, seven different corner sizes, letter-spaced capitals, dashed pills on
every figure, gesture text over the 3D, placeholder sample names, overlapping plan labels, a demo grid
under the 3D set and a generic cube icon in amber. The look is now written down in `Docs/LOOK.md`
(two radii, one button shape, sentence-case labels, the stop scale as the signature colour, Home as a
list of your work) and `scripts/check-look.mjs` fails the build on the mechanical parts. (D-013 to
D-015 were left for the open grip, studio and camera PRs.)

## D-017 · People stay out of the furniture — 2026-11-12

Vorbi saw a standing person inside the sofa in the 3D view. People are now settled against the plan's
set pieces whenever a person or a piece is edited (`Core/Models/Placement.swift` ↔ `web/src/model/placement.ts`,
same cases tested on both sides):

- A standing person is moved to the nearest clear floor beside a piece (never through a wall).
- A sitting person dropped on or next to a sofa, chair or bed sits on it: hips on the seat, facing out
  (a turn of up to 45° is kept), at the seat's height, stored as the optional `seatHeight` on the person.
  Switching a person to Sitting within 0.6 m of a seat sits them on it; switching back to Standing steps
  them out in front.
- Seated people move with their sofa when it is moved or turned; a piece moved onto a standing person
  pushes them aside. People saved earlier are settled once when the plan opens.
- Seat heights are the drawn shapes (sofa cushion ≤ 0.44 m, chair ≤ 0.485 m, bed mattress), not measurements,
  and no figure is shown for them. The iPhone now draws sofas, chairs and beds with a seat, back and arms
  (scanned ones too) instead of solid boxes, so a seated figure isn't hidden inside the box.
- Not covered: people overlapping each other, lights or stands; furniture overlapping furniture.
