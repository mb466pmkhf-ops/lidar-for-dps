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

## D-003 · Build on the latest branch — 2026-10-20
The newest work (Object Capture, viewfinder rebuild, Poppins theme) is on `claude/dreamy-archimedes-lo0whf`
and is not merged into the default branch `claude/framescout-ios-app-pbswdo`. New work branches from
`claude/dreamy-archimedes-lo0whf` to avoid conflicts; the owner should decide which branch becomes `main`.

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
- Scan alignment is a stored correction (`ScanRecord.alignment`), applied to the whole 3D world (scan, cameras,
  lights, people) so positions stay consistent; the scan files and the 2D plan are not changed.
