#!/usr/bin/env bash
# Compiles FrameScout's platform-independent core with the test driver and runs it.
set -euo pipefail
cd "$(dirname "$0")/.."
CORE=FrameScout/Core
OUT="${TMPDIR:-/tmp}/framescout-core-tests-bin"
swiftc -swift-version 5 -O -o "$OUT" \
  Tests/CoreLogicTests/main.swift \
  $CORE/Models/*.swift \
  $CORE/Services/Optics.swift $CORE/Services/SolarCalculator.swift $CORE/Services/UnitsFormatter.swift \
  $CORE/Geometry/SceneGeometry.swift $CORE/Geometry/WallBuilder.swift $CORE/Geometry/MeshScanData.swift $CORE/Geometry/PlanGeometry.swift \
  $CORE/Export/ZipArchive.swift $CORE/Export/GLBWriter.swift $CORE/Export/USDAWriter.swift $CORE/Export/OBJWriter.swift
"$OUT"
