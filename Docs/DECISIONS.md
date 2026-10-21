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
