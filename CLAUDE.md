# FrameScan (code name FrameScout)

iPhone LiDAR location-scouting app for cinematographers. Product working name is **FrameScan**; the
Xcode project, target, bundle and Swift types are still `FrameScout` (see `Docs/DECISIONS.md`, D-001).

Read first: `Docs/PRODUCT_BRIEF.md`, `Docs/ARCHITECTURE.md` (the technical guide), `Docs/DECISIONS.md`.

## Conventions

- Swift 5 language mode, SwiftUI, iOS 17+, no third-party dependencies, offline-first.
- `Core/` never imports SwiftUI. Capture (`Features/Scanning`, ARKit/RoomPlan) stays out of `Core/Models`.
- Every figure shown to a user carries a `Provenance` (measured / estimated / manual). New figures must
  pick one; don't present a heuristic as a measurement.
- Model fields added to `Codable` types must be optional or have custom decoding so older project files load.
- New Swift files under `FrameScout/` are picked up automatically (Xcode folder-synchronised groups).
- Location scans are private data: no network upload, analytics or third-party SDKs without a decision entry.

## Verifying

- `Tests/run_core_tests.sh` compiles the platform-independent core and runs `Tests/CoreLogicTests` (macOS/Linux).
  If you add a Core file outside `Core/Models`, add it to the script.
- CI (`.github/workflows/build.yml`) builds the iOS app unsigned with Xcode and runs the core tests.
- Scanning, permissions and UI can only be checked on a real LiDAR device. Say so when you couldn't.
