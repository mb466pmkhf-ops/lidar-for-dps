#!/usr/bin/env python3
"""Release gate: catches App Store rejections that can be checked without a device.

- The privacy manifest exists, declares no tracking, and gives a reason for every required-reason
  API the Swift code calls.
- Info.plist answers export compliance and has a usage text for every permission the code asks for.
- Account deletion is still reachable when account creation is.
"""
import plistlib
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
src = root / "FrameScout"
code = "\n".join(p.read_text(encoding="utf-8") for p in src.rglob("*.swift"))
problems = []

manifest_path = src / "Resources" / "PrivacyInfo.xcprivacy"
if not manifest_path.exists():
    problems.append("FrameScout/Resources/PrivacyInfo.xcprivacy is missing")
    manifest = {}
else:
    manifest = plistlib.loads(manifest_path.read_bytes())
    if manifest.get("NSPrivacyTracking") is not False:
        problems.append("Privacy manifest must say NSPrivacyTracking = false")

declared = {e["NSPrivacyAccessedAPIType"] for e in manifest.get("NSPrivacyAccessedAPITypes", [])}
required_reason = {
    "NSPrivacyAccessedAPICategoryUserDefaults": r"\bUserDefaults\b|@AppStorage",
    "NSPrivacyAccessedAPICategoryFileTimestamp": r"creationDate|modificationDate|contentModificationDateKey|NSFileModificationDate|attributesOfItem",
    "NSPrivacyAccessedAPICategorySystemBootTime": r"systemUptime|mach_absolute_time",
    "NSPrivacyAccessedAPICategoryDiskSpace": r"volumeAvailableCapacity|systemFreeSize|NSFileSystemFreeSize",
    "NSPrivacyAccessedAPICategoryActiveKeyboards": r"activeInputModes",
}
for category, pattern in required_reason.items():
    if re.search(pattern, code) and category not in declared:
        problems.append(f"Code uses a {category.removeprefix('NSPrivacyAccessedAPICategory')} API but the privacy manifest gives no reason")

info = plistlib.loads((root / "Config" / "Info.plist").read_bytes())
if "ITSAppUsesNonExemptEncryption" not in info:
    problems.append("Info.plist needs ITSAppUsesNonExemptEncryption (export compliance)")
usage = {
    "NSCameraUsageDescription": r"\bARSession\b|RoomCaptureSession|AVCaptureDevice|ObjectCaptureSession",
    "NSLocationWhenInUseUsageDescription": r"CLLocationManager",
    "NSMotionUsageDescription": r"CMMotionManager|CMHeadingManager",
    "NSPhotoLibraryAddUsageDescription": r"PHPhotoLibrary\.shared\(\)\.performChanges|UIImageWriteToSavedPhotosAlbum",
    "NSMicrophoneUsageDescription": r"AVAudioRecorder|AVAudioSession\.sharedInstance\(\)\.requestRecordPermission",
}
for key, pattern in usage.items():
    if re.search(pattern, code) and not info.get(key):
        problems.append(f"Code needs {key} in Info.plist")

if "createAccount" in code and "deleteAccount" not in code:
    problems.append("The app creates accounts but has no way to delete one (App Store rule 5.1.1(v))")

if problems:
    print("App Store rule check failed:\n  " + "\n  ".join(problems))
    sys.exit(1)
print("App Store rule check passed.")
