# FrameScout

**LiDAR location scouting and previs for cinematographers.** Scan a location with an iPhone/iPad Pro, measure it, plan camera positions and lenses against the real walls, check the sun, and take the space into Unreal Engine.

Built for DOPs, camera operators, directors and location managers. Every screen answers a production question:

| Question | Where |
|---|---|
| How big is the room? What's the ceiling height? | Room Scan → key figures, auto measurements |
| Where are the windows and doors? | Plan (doors with swing arcs, windows in blue) |
| Where can I put the camera? How much room behind it? | Plan → `+ Camera`, clearance readout (behind / front / left / right) |
| Can I get a 32 mm wide shot from here? | Plan → Frame in 3D (virtual cinema camera in the scan) · Lens Viewfinder |
| How far from the actor for a full shot? | Lens calculator (any lens/sensor) |
| Which direction does the light come from at 4 pm? | Sun & Light (sun path, windows in direct sun, times of direct sun per window) |
| Can I bring this into Unreal? | Export → Unreal preset (GLB / USD / cm-Z-up OBJ / CineCamera CSV) |
| Can I show the director the space? | 3D view, top-down plan, location package ZIP |

## Requirements

- **Xcode 16 or later** (the project uses Xcode 16 folder-synchronised groups).
- **iOS 17.0+**.
- **LiDAR device for scanning**: iPhone 12 Pro / 13 Pro / 14 Pro / 15 Pro / 16 Pro (and later Pro models), iPad Pro 2020 or later. Other devices run the app with reduced functionality (see below).

## Build & run on an iPhone

1. Open `FrameScout.xcodeproj`.
2. Select the **FrameScout** target → *Signing & Capabilities* → choose your **Team**. Change the bundle identifier (`com.framescout.app`) to something unique, e.g. `com.yourname.framescout`.
3. Plug in a LiDAR iPhone/iPad, select it as the run destination, press **Run**.
4. First launch asks for Camera, Location (for sun maths) and Motion (for north) permission.

The simulator builds, but RoomPlan/ARKit scanning only works on a real LiDAR device.

## Features (MVP status)

| # | Feature | Status | Implementation |
|---|---|---|---|
| 1 | Project management (create, rename, duplicate, delete, import/export) | ✅ | `ProjectStore` — local JSON + assets, offline |
| 2 | LiDAR room scanning with live stats, pause/resume, photos during scan | ✅ | RoomPlan `RoomCaptureView`; pause = segment stop, resume = new segment, merged with `StructureBuilder` |
| 2b | LiDAR mesh scanning (exteriors, irregular spaces) | ✅ | ARKit scene reconstruction with classification, live mesh overlay |
| 3 | Saving scans (raw RoomPlan JSON, mesh, derived plan & stats) | ✅ | `ScanSaver` |
| 4 | Measurement: AR tape / rangefinder / height; plan measure with wall snapping; auto room measurements; manual | ✅ | `ARMeasureView`, `PlanEditorView`, `MeasurementListView` |
| 5 | Photos (camera, library, snapped during scans with pose) and notes (general, lighting, production, quick scout notes, tags) | ✅ | `PhotoGalleryView`, `LocationNotesView` |
| 6 | Camera positions: position, height (with tripod presets), pan/tilt, lens, sensor, notes, FOV wedge on plan, clearance | ✅ | `PlanEditorView`, `CameraRigForm` |
| 7 | Lens/FOV: AR-free director's viewfinder with frame lines for any lens/sensor/aspect, auto phone-lens switching; virtual camera in the scan | ✅ | `ViewfinderView` (AVFoundation), `VirtualCameraView` (SceneKit) |
| 8 | USD / USDZ export | ✅ | `USDAWriter` (+ Apple's native RoomPlan USDZ) |
| 9 | OBJ and GLB export | ✅ | `OBJWriter`, `GLBWriter` (validated with the Khronos glTF validator) |
| 10 | Shot planning: SHOT 01, 02… with camera, lens, height, direction, subject mark, notes, reference photo, top-down view | ✅ | `ShotListView` |
| 11 | Sun & light: azimuth/elevation, sunrise/sunset/golden hour, sun on the plan, window direct-sun times | ✅ | `SolarCalculator` (NOAA), `SunLightView` |
| 12 | Unreal export workflow | ✅ | Unreal preset, cameras in GLB, CineCamera CSV, `Docs/UNREAL_WORKFLOW.md` |
| — | Location comparison (A vs B vs C) | ✅ | `CompareView` |
| — | Location package ZIP | ✅ | `ExportService` + dependency-free `ZipWriter` |
| — | PDF scout report (plan with cameras/shots, key figures, photos, measurements, notes) | ✅ | `ScoutReport` (SwiftUI `ImageRenderer` → PDF), in packages and Location › ⋯ menu |

### Devices without LiDAR

The app tells the user plainly that 3D scanning needs LiDAR and keeps everything else working: projects, locations, photos, notes, tags, **AR measure** (plane-based, with an accuracy note), **lens viewfinder**, **sun tools**, camera/shot planning on a blank 1 m grid, comparison and export of non-scan data. Scans made on a LiDAR device can be moved over via *Export Project Backup* → *Import Project Backup*.

## Location package

```
LOCATION_NAME/
  Scan/
    location.usdz  location.glb  location.obj/.mtl  [location.usda]  [location_roomplan_apple.usdz]
    Unreal/  location_unreal_cm_zup.obj  cameras_unreal.csv  README_UNREAL.md
  Photos/               001_caption.jpg …
  Measurements/         measurements.json  measurements.csv
  Camera_Positions/     camera_positions.json  shots.json
  Notes/                notes.txt  Scout_Report.pdf
  Metadata/             metadata.json  location.json  floor_plan.json  roomplan_captured_rooms.json
```

`metadata.json` is machine-readable: coordinate system (metres, +Y up, −Z forward), GPS, compass north offset, scan statistics, file list and photo poses.

## Honest limitations (and what we do instead)

| Limitation | Closest useful alternative in FrameScout |
|---|---|
| RoomPlan and ARKit meshes have **no textures** | Flat PBR colours per surface type; reference photos exported separately with their scan poses. Texture baking is on the roadmap. |
| RoomPlan **doesn't detect ceilings** | Ceiling height from wall heights; optional estimated ceiling slab in exports. Mesh scans classify real ceiling triangles. |
| RoomPlan has **no completeness metric** | Clearly labelled *estimated* completeness from wall-loop closure, detection confidence and floor detection. |
| No **native pause** in RoomPlan | Pause stops a segment while keeping the AR world; resume starts a new segment; segments merge with `StructureBuilder` (also enables multi-room). |
| iOS has **no FBX/Unreal SDK** | Unreal-friendly GLB (recommended), USD, and a cm/Z-up OBJ + CineCamera CSV, with an import guide. |
| **Indoor compass** error (10–20°) | North offset is sampled throughout the scan and is editable in Sun & Light (calibrate north). |
| ARKit only exposes the **1× camera** | The lens viewfinder uses AVFoundation instead, switching to the ultra-wide for wide cinema lenses. |
| RoomPlan works **indoors only** | Mesh Scan mode for exteriors (LiDAR range ≈ 5 m). |

## Tests

`Tests/run_core_tests.sh` compiles the platform-independent core (optics, NOAA sun, plan geometry, wall hole cutting, mesh storage, GLB/USD/OBJ writers, ZIP/USDZ) and runs the checks — it works on macOS and Linux. CI (`.github/workflows/build.yml`) builds the iOS app with Xcode and validates generated files with the Khronos glTF validator and Pixar's USD library.

## Documentation

- [`Docs/ARCHITECTURE.md`](Docs/ARCHITECTURE.md) — module layout, data model, storage, coordinate conventions.
- [`Docs/UNREAL_WORKFLOW.md`](Docs/UNREAL_WORKFLOW.md) — getting a scan into Unreal Engine.
- [`Docs/ROADMAP.md`](Docs/ROADMAP.md) — future features and where they plug in.
