# FrameScout architecture

Native Swift / SwiftUI app, iOS 17+, no third-party dependencies. Offline-first: all data lives in the app's Documents folder (visible in the Files app).

```
FrameScout/
  App/                 App entry, navigation (Route), capture flows (full-screen camera UIs)
  Core/
    Models/            Codable value types: Project, Location, ScanRecord, FloorPlan,
                       DistanceMeasurement, CameraRig/CameraPosition/Shot, SensorFormat, ReferencePhoto
    Persistence/       ProjectStore (ObservableObject, debounced JSON writes), StoragePaths, ScanAssets
    Services/          DeviceCapabilities, Optics, SolarCalculator (NOAA), HeadingEstimator (CoreMotion),
                       LocationProvider (CoreLocation), UnitsFormatter
    Geometry/          SceneGeometry (format-neutral scene graph), RoomPlanConverter, MeshScanData,
                       WallBuilder (door/window hole cutting), PlanGeometry (clearance, snapping)
    Export/            USDAWriter (+USDZ), GLBWriter, OBJWriter, ZipWriter/ZipReader, ExportService
  Features/            One folder per screen/flow: Home, Projects, Location, Scanning, Measure, Plan,
                       Camera (rig editor, viewfinder, virtual camera), Shots, Sun, Compare, Export, Photos
  Shared/              Theme (dark palette, type), reusable components
  Resources/           Asset catalog
Tests/                 Platform-independent core tests (run on macOS or Linux)
```

**Rule of thumb:** `Core/` never imports SwiftUI. Everything in `Core/Models`, `Core/Geometry` (except `RoomPlanConverter`), `Core/Export` (except `ExportService`), `Optics` and `SolarCalculator` is pure Swift + Foundation and is unit-tested on Linux in CI.

## Data model

```
Project ─┬─ Location ─┬─ ScanRecord[]        (stats + north offset; heavy data on disk)
         │            ├─ ReferencePhoto[]    (JPEG on disk; optional pose inside a scan)
         │            ├─ DistanceMeasurement[]
         │            ├─ CameraPosition[] ── CameraRig
         │            ├─ Shot[] ──────────── CameraRig + subject mark + photo
         │            └─ notes, lighting/production notes, quick notes, tags, GPS
```

`CameraRig` (position, height, pan, tilt, focal length, sensor, frame aspect) is shared by camera positions and shots, so future features (dolly tracks, crane arcs) extend one type.

## Storage layout

```
Documents/Projects/<projectID>/project.json
Documents/Projects/<projectID>/Locations/<locationID>/Photos/<uuid>.jpg
Documents/Projects/<projectID>/Locations/<locationID>/Scans/<scanID>/
    rooms.json        RoomPlan CapturedRoom segments (Codable, lossless)
    structure.json    merged CapturedStructure (multi-segment scans)
    roomplan.usdz     Apple's own parametric USDZ (single-room scans)
    mesh.fsmesh       LiDAR mesh: positions, normals, indices, per-face ARKit classification
    plan.json         derived top-down FloorPlan used by every 2D view
Documents/Exports/    generated ZIP packages
```

Raw RoomPlan data is kept so exports can be regenerated when exporters improve.

## Coordinate conventions

- Scan space = ARKit world: metres, right-handed, **+Y up, −Z forward**, origin where the scan started.
- Plan space: `x` → screen right, `z` → screen down (top-down, −Z at the top).
- **World bearing**: 0° = −Z, clockwise seen from above (90° = +X). Camera pan uses this.
- **North offset** (`ScanRecord.northOffset`): true-north bearing of the −Z axis. True bearing = north offset + world bearing.
- Unreal conversion (OBJ preset & CSV): `UE(x, y, z) = (−z, x, y) × 100` (cm, X forward, Z up); UE yaw = pan, pitch = tilt.

## Scanning pipeline

```
RoomCaptureView ── live CapturedRoom ──► RoomElements ──► FloorPlan + ScanStats (HUD)
      │ pause = stop(pauseARSession: false)  resume = run()  → segments[]
      ▼ finish
StructureBuilder (≥2 segments) ──► ScanSaver.prepare (background):
      rooms.json / structure.json / roomplan.usdz / plan.json + ScanRecord
ARView (scene reconstruction) ──► ARMeshAnchor[] ──► MeshExtractor ──► MeshScanData ──► plan/stats
HeadingEstimator: CoreMotion (true north) × AR camera pose ──► northOffset (circular mean)
```

## Export pipeline

```
ScanAssets.geometry(scan) ──► SceneGeometry (named groups, metres, Y-up, PBR colours)
        ├─► USDAWriter ──► .usda / .usdz (ZipWriter, 64-byte aligned, uncompressed)
        ├─► GLBWriter  ──► .glb (+ glTF cameras for camera positions & shots)
        └─► OBJWriter  ──► .obj/.mtl (metres Y-up, or Unreal cm Z-up)
ExportService ──► location/project package folder ──► ZipWriter ──► Documents/Exports/*.zip
```

## Concurrency

Swift 5 language mode. UI state is `@MainActor`; heavy work (encoding, mesh extraction, exports) runs in detached tasks on value copies. RoomPlan/ARKit delegate callbacks hop to the main actor.
