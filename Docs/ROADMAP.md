# Roadmap — designed-for extensions

Each item lists where it plugs into the current architecture.

| Feature | Hook |
|---|---|
| iPhone camera metadata (EXIF lens, focal length) on reference photos | `ReferencePhoto` (add optional metadata struct); `ViewfinderModel.capture` already knows the phone lens |
| ARRI / Sony / RED camera presets (bodies with multiple recording modes) | `SensorLibrary` → group `SensorFormat`s under a `CameraBody` type; `SensorPicker` menu is already grouped by manufacturer |
| Depth map export | `FrameGrabber` — capture `ARFrame.sceneDepth` alongside the JPEG in `PendingPhoto` |
| Point-cloud export (PLY / E57) | New writer in `Core/Export` fed from `MeshScanData.positions` or accumulated `sceneDepth` points |
| LiDAR mesh cleanup / decimation | `MeshScanData` → add a `simplified(targetFaces:)` pass before `sceneGeometry()` |
| Automatic room measurements (full dimensioning) | `MeasurementListView.generateFromScan` + `PlanGeometry` (wall-to-wall pairs from parallel walls) |
| Virtual dolly tracks | New `DollyTrack { start, end, rig }` on `Location`; draw in `PlanRenderer`; clearance via `PlanGeometry.clearance` along the path |
| Tripod height presets | Implemented as `HeightPreset` — make user-editable |
| Crane / jib clearance checks | `CameraRig` + arm length; sweep circle vs walls/ceiling height in `PlanGeometry` |
| Lighting stand / fixture placement, Fresnel beam angles | New `LightFixture { position, height, pan, tilt, beamAngle, type }` on `Location`, drawn as cones in `PlanRenderer`, exported as glTF `KHR_lights_punctual` spot lights |
| Diffusion frame / negative fill planning | Same fixture model with `kind = .frame(size)`; rectangles in plan and 3D |
| Crew / equipment clearance | Occupancy zones (rectangles) on the plan; `PlanGeometry` overlap checks |
| Generate a simple Unreal scene | Emit a Python script for Unreal's Editor Scripting that imports the GLB, spawns CineCameraActors from the CSV and sets up the Sun Position Calculator |
| Texture baking | Accumulate `ARFrame` images with poses during scanning; project onto the mesh (or hand off to PhotogrammetrySession on Mac) |
| Sync between devices / iCloud backup | `ProjectStore` is file-based per project → move `projectsRoot` into an iCloud ubiquity container with `NSFileCoordinator`; conflict resolution on `modifiedAt` |
| PDF location reports / shareable scout reports | ✅ Done — `ScoutReport`. Next: branded cover page, sun diagram page |
| Multi-user production projects | Requires an account/backend; keep optional — local-first remains the default |
