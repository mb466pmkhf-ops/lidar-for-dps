import ARKit
import AVFoundation
import Foundation
import RoomPlan

/// What this device can actually do. Everything that needs LiDAR is gated on these checks.
enum DeviceCapabilities {
    /// LiDAR sensor present (scene reconstruction requires it).
    static var hasLiDAR: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    /// RoomPlan requires LiDAR + A12 or later.
    static var supportsRoomPlan: Bool { RoomCaptureSession.isSupported }

    static var supportsMeshClassification: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
    }

    /// AR world tracking (all ARKit devices). Used for the non-LiDAR measure fallback.
    static var supportsWorldTracking: Bool { ARWorldTrackingConfiguration.isSupported }

    static var hasCamera: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    /// Hardware identifier such as "iPhone15,3".
    static var modelIdentifier: String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        return mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
    }

    static var summary: String {
        if supportsRoomPlan { return "LiDAR ready · Room + Mesh scanning available" }
        if hasLiDAR { return "LiDAR available · Mesh scanning available" }
        if supportsWorldTracking { return "No LiDAR · AR measure (plane-based), viewfinder, notes and sun tools available" }
        return "No AR support · viewfinder, notes and sun tools available"
    }
}
