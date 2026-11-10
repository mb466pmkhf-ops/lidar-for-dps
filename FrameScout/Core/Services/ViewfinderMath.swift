import Foundation

/// Pure maths behind the lens viewfinder: what a cinema lens sees, how big that is on the
/// phone's preview, and which phone zoom makes it fill the screen. Kept free of AVFoundation
/// so it is unit tested on any platform.
///
/// Model: the phone image is a pinhole camera whose long side spans `phoneFOV` degrees at
/// zoom 1. Zooming by `z` divides tan(fov/2) by `z` (that is how AVFoundation's fused
/// multi-camera reports `videoZoomFactor`, relative to its widest lens).
enum ViewfinderMath {
    struct Size: Equatable {
        var width: Double
        var height: Double
    }

    /// Desqueezed image area of a cinema camera (mm) after fitting the delivery aspect ratio.
    /// Anamorphic lenses squeeze horizontally, so the sensor width is multiplied by `squeeze`
    /// before the frame lines are fitted.
    static func imageArea(sensor: SensorFormat, aspect: FrameAspect, squeeze: Double) -> Size {
        var desqueezed = sensor
        desqueezed.width = sensor.width * max(1, squeeze)
        let area = Optics.imageArea(sensor: desqueezed, aspect: aspect)
        return Size(width: area.width, height: area.height)
    }

    /// Horizontal / vertical angle of view (degrees) of the cinema frame.
    static func targetFOV(focalLength: Double, sensor: SensorFormat, aspect: FrameAspect, squeeze: Double) -> Size {
        let area = imageArea(sensor: sensor, aspect: aspect, squeeze: squeeze)
        return Size(width: Optics.fieldOfView(size: area.width, focalLength: focalLength),
                    height: Optics.fieldOfView(size: area.height, focalLength: focalLength))
    }

    /// FOV of the phone image's long side at a zoom factor.
    static func effectiveFOV(baseFOV: Double, zoom: Double) -> Double {
        guard zoom > 0 else { return baseFOV }
        return 2 * atan(tan(baseFOV * .pi / 360) / zoom) * 180 / .pi
    }

    /// Size in screen points of the cinema frame drawn on a preview image of `image` points
    /// whose long side spans `phoneFOV` degrees. The frame's horizontal axis is the screen's
    /// x axis in both orientations, so in portrait a wide frame is drawn across the image's
    /// short side.
    static func frameSize(target: Size, image: Size, phoneFOV: Double) -> Size {
        let longSide = max(image.width, image.height)
        guard longSide > 0, phoneFOV > 0, phoneFOV < 180 else { return Size(width: 0, height: 0) }
        let fPixels = longSide / (2 * tan(phoneFOV * .pi / 360))
        return Size(width: 2 * fPixels * tan(target.width * .pi / 360),
                    height: 2 * fPixels * tan(target.height * .pi / 360))
    }

    /// Zoom factor at which the frame occupies `fill` (0...1) of the image in its tighter axis.
    /// Not clamped — compare with the device's zoom range to tell whether it is reachable.
    static func fillZoom(target: Size, image: Size, baseFOV: Double, fill: Double) -> Double {
        let atOne = frameSize(target: target, image: image, phoneFOV: baseFOV)
        guard atOne.width > 0, atOne.height > 0 else { return 1 }
        return min(fill * image.width / atOne.width, fill * image.height / atOne.height)
    }

    /// True when the frame is larger than the image even at the widest zoom.
    static func exceedsImage(target: Size, image: Size, baseFOV: Double, minZoom: Double) -> Bool {
        let frame = frameSize(target: target, image: image,
                              phoneFOV: effectiveFOV(baseFOV: baseFOV, zoom: minZoom))
        return frame.width > image.width * 1.002 || frame.height > image.height * 1.002
    }

    /// Picks a 16:9 phone format for wide frames and 4:3 for squarer ones, so the frame uses as
    /// much of the screen as possible without cropping the top and bottom of tall frames.
    static func prefersWidescreenFormat(target: Size) -> Bool {
        guard target.height > 0 else { return true }
        let ratio = tan(target.width * .pi / 360) / tan(target.height * .pi / 360)
        return ratio >= 1.6
    }

    // MARK: Level

    struct Attitude: Equatable {
        /// Rotation of the image horizon away from level, degrees. Positive = device turned clockwise.
        var roll: Double
        /// Elevation of the back camera's optical axis, degrees. Positive = looking up.
        var tilt: Double
    }

    /// Roll and tilt from a gravity vector in device coordinates (x right, y up, z out of the
    /// screen; unit length ≈ 1 g). Roll is measured from whichever of the four upright
    /// orientations is nearest, so it works in portrait and both landscapes.
    static func attitude(gravityX gx: Double, gravityY gy: Double, gravityZ gz: Double) -> Attitude {
        let tilt = asin(max(-1, min(1, gz))) * 180 / .pi
        var angle = atan2(gx, -gy) * 180 / .pi
        let nearest = (angle / 90).rounded() * 90
        angle -= nearest
        return Attitude(roll: angle, tilt: tilt)
    }

    /// Snap to the next / previous common focal length (for pinch and swipe stepping).
    static func steppedFocalLength(from current: Double, by step: Int, in lenses: [Double] = LensLibrary.commonFocalLengths) -> Double {
        guard !lenses.isEmpty, step != 0 else { return current }
        if step > 0 {
            let next = lenses.filter { $0 > current + 0.01 }
            return next.dropFirst(step - 1).first ?? lenses.last!
        } else {
            let prev = lenses.filter { $0 < current - 0.01 }
            return prev.dropLast(-step - 1).last ?? lenses.first!
        }
    }
}
