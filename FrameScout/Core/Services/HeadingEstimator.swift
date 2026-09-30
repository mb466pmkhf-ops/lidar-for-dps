import ARKit
import CoreMotion
import Foundation
import simd

/// Works out which way true north points inside an ARKit/RoomPlan world.
///
/// RoomPlan runs its own gravity-aligned session, so the world -Z axis points wherever the phone
/// faced at start. We sample CoreMotion's north-referenced attitude alongside the AR camera pose
/// and store the offset. Indoors, steel and electrics disturb the magnetometer, so the result
/// is labelled approximate and can be corrected by hand later.
final class HeadingEstimator {
    private let motion = CMMotionManager()
    private var samples: [Double] = []
    private(set) var referenceFrame: CMAttitudeReferenceFrame?

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        let available = CMMotionManager.availableAttitudeReferenceFrames()
        if available.contains(.xTrueNorthZVertical) {
            referenceFrame = .xTrueNorthZVertical
        } else if available.contains(.xMagneticNorthZVertical) {
            referenceFrame = .xMagneticNorthZVertical
        } else {
            return
        }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(using: referenceFrame!)
    }

    func stop() { motion.stopDeviceMotionUpdates() }

    /// Call periodically with the current AR frame (tracking must be normal).
    func sample(frame: ARFrame) {
        guard case .normal = frame.camera.trackingState,
              let deviceMotion = motion.deviceMotion else { return }

        // Back-camera direction (device -Z) in the north-referenced frame (X north, Y west, Z up).
        // The rotation matrix maps between device and reference frames; rather than rely on its
        // transpose convention, pick the reading that correctly predicts the measured gravity
        // (reference "down" is (0,0,-1)). The camera direction is then the other third vector.
        let m = deviceMotion.attitude.rotationMatrix
        let g = deviceMotion.gravity
        let column3 = SIMD3<Double>(m.m13, m.m23, m.m33)
        let row3 = SIMD3<Double>(m.m31, m.m32, m.m33)
        let gravity = SIMD3<Double>(g.x, g.y, g.z)
        let errorIfColumn = simd_length(-column3 - gravity)
        let errorIfRow = simd_length(-row3 - gravity)
        let look = errorIfColumn <= errorIfRow ? -row3 : -column3
        let horizontal = (look.x * look.x + look.y * look.y).squareRoot()
        guard horizontal > 0.35 else { return } // pointing at floor/ceiling: heading unreliable
        let trueBearing = atan2(-look.y, look.x) * 180 / .pi

        // Same direction in ARKit world space.
        let t = frame.camera.transform
        let forward = SIMD3<Double>(-Double(t.columns.2.x), 0, -Double(t.columns.2.z))
        guard (forward.x * forward.x + forward.z * forward.z) > 0.1 else { return }
        let worldBearing = PlanPoint(x: forward.x, z: forward.z).worldBearing

        var offset = (trueBearing - worldBearing).truncatingRemainder(dividingBy: 360)
        if offset < 0 { offset += 360 }
        samples.append(offset)
        if samples.count > 600 { samples.removeFirst(samples.count - 600) }
    }

    /// Circular mean of the samples: bearing (deg from true north) of world -Z.
    var northOffset: Double? {
        guard samples.count >= 5 else { return nil }
        var s = 0.0, c = 0.0
        for a in samples {
            s += sin(a * .pi / 180)
            c += cos(a * .pi / 180)
        }
        let mean = atan2(s, c) * 180 / .pi
        return mean < 0 ? mean + 360 : mean
    }

    var sampleCount: Int { samples.count }
}
