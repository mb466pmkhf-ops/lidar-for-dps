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
- **Not modelled, and said so on screen**: light bouncing round the room, daylight, and bounce boards. The
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
