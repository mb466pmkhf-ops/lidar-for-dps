# From location scan to Unreal Engine

## What FrameScout exports

| File | Units / axes | Contents |
|---|---|---|
| `Scan/location.glb` | metres, Y-up (glTF standard) | Full hierarchy (`Walls/Wall_01`, `Doors`, `Windows`, `Floors`, `Furniture`, `LiDAR_Mesh/*`), PBR colours, glTF **cameras** for every camera position and shot, metadata in `extras` |
| `Scan/location.usdz` (+ optional `.usda`) | `metersPerUnit = 1`, `upAxis = "Y"` | Same hierarchy as Xforms + Meshes, `UsdPreviewSurface` materials, metadata in `customData` |
| `Scan/location.obj` + `.mtl` | metres, Y-up | Groups per element, for any DCC |
| `Scan/Unreal/location_unreal_cm_zup.obj` | **centimetres, Z-up, X-forward** (Unreal space) | Same geometry pre-converted to Unreal units/axes |
| `Scan/Unreal/cameras_unreal.csv` | cm, degrees | `Name, X, Y, Z, Pitch, Yaw, Roll, FocalLength_mm, SensorWidth_mm, SensorHeight_mm` |
| `Scan/location_roomplan_apple.usdz` | Apple RoomPlan native | Apple's own parametric export (single-room scans) |

Room scans export clean parametric geometry. Walls are solid boxes with **real openings cut for doors and windows**, so daylight can enter. Glass panes and door leaves are separate objects. Mesh scans export the LiDAR surface split by ARKit classification.

## Recommended: GLB (UE 5.1+)

1. Unzip the location package on your workstation.
2. In the Content Browser, **Import** `Scan/location.glb` (Interchange glTF importer, built in). Or drag it into the viewport with *Import Into Level* to keep the hierarchy and spawn the cameras.
3. Scale and orientation are correct automatically (glTF metres/Y-up → Unreal cm/Z-up).
4. Cameras come in as camera actors with the right field of view. For exact filmback, set each CineCameraActor's *Filmback* and *Focal Length* from `cameras_unreal.csv`.

## USD

1. Enable **Edit → Plugins → USD Importer**, restart.
2. *File → Import Into Level* → `location.usdz`, or add a **USD Stage Actor** and point it at `location.usda` for a live-linked stage.

## OBJ (fallback / older engines)

- `Scan/Unreal/location_unreal_cm_zup.obj`: *Import Uniform Scale* 1.0, no rotation. Untick *Combine Meshes* to keep walls, doors and furniture separate.
- `Scan/location.obj`: generic metres/Y-up; in Unreal use *Import Uniform Scale* 100 and rotate X +90° if needed.

## Placing cameras from the CSV

Each row maps directly onto a **CineCameraActor**:
- Location = `X_cm, Y_cm, Z_cm`
- Rotation = `Pitch_deg` (Y), `Yaw_deg` (Z), `Roll_deg` (X)
- Filmback = `SensorWidth_mm × SensorHeight_mm` (already cropped to the chosen frame aspect)
- Current Focal Length = `FocalLength_mm`

The CSV can also be imported as a Data Table with a matching struct, and an Editor Utility Blueprint can spawn the cameras.

## Sun / daylight

`Metadata/metadata.json` includes the GPS position and `true_north_bearing_of_minus_z_deg`. In Unreal, Unreal +X corresponds to the scan's −Z. Use the **Sun Position Calculator** plugin (or a Directional Light):
- Set latitude/longitude from the metadata.
- Rotate the *North Offset* by the value in `README_UNREAL.md` so the sun comes through the same windows as the Sun & Light screen predicts.

## Why not FBX / .umap directly?

iOS has no Autodesk FBX SDK and no Unreal asset writer, and generating `.uasset` files outside the editor isn't supported. GLB and USD are both first-class import formats in current Unreal versions and keep scale, orientation, hierarchy, materials and cameras. So FrameScout writes those, cleanly, rather than a lossy workaround.

## Known limitations

- No photo textures: RoomPlan and ARKit don't capture them. Use reference photos from `Photos/` for look-dev.
- RoomPlan doesn't detect ceilings; tick *Estimated ceiling* in export options to add a flat ceiling at wall height.
- Large mesh scans (> 1M triangles) import faster after decimation (Unreal *Nanite* also handles them well).
