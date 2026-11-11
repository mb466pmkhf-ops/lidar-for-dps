import UIKit
import Vision

/// Reads printed text (a studio's spec sheet, a floor plan legend, a screenshot of a website) out of a
/// photo with Apple's on-device text recognition. Nothing leaves the phone. The result only feeds the
/// listing text box, where the user can see and correct it before any size is used.
enum ListingPhotoText {
    static func read(_ image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "" }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) { () -> String in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // Language correction "fixes" figures like 15m into words, so it stays off.
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation)
            do { try handler.perform([request]) } catch { return "" }
            let lines = (request.results ?? [])
                .compactMap { obs -> (CGRect, String)? in
                    guard let text = obs.topCandidates(1).first?.string else { return nil }
                    return (obs.boundingBox, text)
                }
                // Top to bottom, then left to right. Vision's origin is the bottom-left corner.
                .sorted { a, b in
                    abs(a.0.midY - b.0.midY) > 0.01 ? a.0.midY > b.0.midY : a.0.minX < b.0.minX
                }
                .map(\.1)
            return lines.joined(separator: "\n")
        }.value
    }
}

private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
