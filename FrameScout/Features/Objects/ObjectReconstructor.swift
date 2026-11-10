import Foundation
import QuickLookThumbnailing
import RealityKit
import UIKit

/// Builds the textured model from captured images on the phone (RealityKit
/// `PhotogrammetrySession`), then derives the Unreal-friendly GLB and a thumbnail.
/// Interrupted builds resume from the checkpoint folder.
@MainActor
final class ObjectReconstructor: ObservableObject {
    enum Phase: Equatable {
        case idle
        case running
        case converting
        case finished
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0

    private var session: PhotogrammetrySession?
    private var task: Task<Void, Never>?

    static var isSupported: Bool { PhotogrammetrySession.isSupported }

    var isBusy: Bool { phase == .running || phase == .converting }

    func run(store: ProjectStore, projectID: UUID, objectID: UUID) {
        guard !isBusy else { return }
        guard Self.isSupported else {
            phase = .failed("Building models on the phone needs a LiDAR iPhone or iPad Pro (iPhone 12 Pro or later) on iOS 17. The capture images are saved — you can build the model on a Mac instead.")
            return
        }
        let images = StoragePaths.objectFile(projectID, objectID: objectID, .images)
        let checkpoint = StoragePaths.objectFile(projectID, objectID: objectID, .checkpoint)
        let usdz = StoragePaths.objectFile(projectID, objectID: objectID, .usdz)
        let glb = StoragePaths.objectFile(projectID, objectID: objectID, .glb)
        let thumbnail = StoragePaths.objectFile(projectID, objectID: objectID, .thumbnail)
        let name = store.object(projectID, objectID)?.name ?? "Object"
        StoragePaths.ensureDirectory(checkpoint)

        phase = .running
        progress = 0
        UIApplication.shared.isIdleTimerDisabled = true
        task = Task {
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            do {
                var configuration = PhotogrammetrySession.Configuration()
                configuration.checkpointDirectory = checkpoint
                let session = try PhotogrammetrySession(input: images, configuration: configuration)
                self.session = session
                try session.process(requests: [.modelFile(url: usdz)])
                outputs: for try await output in session.outputs {
                    switch output {
                    case .requestProgress(_, let fraction):
                        self.progress = fraction
                    case .requestError(_, let error):
                        throw error
                    case .processingCancelled:
                        throw CancellationError()
                    case .processingComplete:
                        break outputs
                    default:
                        break
                    }
                }
                self.session = nil
                guard FileManager.default.fileExists(atPath: usdz.path) else {
                    throw NSError(domain: "FrameScout", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Reconstruction finished without a model file."])
                }

                self.phase = .converting
                let summary = try await Task.detached(priority: .userInitiated) {
                    try ObjectModelConverter.writeGLB(usdz: usdz, to: glb, name: name)
                }.value
                if let jpeg = await Self.thumbnail(for: usdz) {
                    try? jpeg.write(to: thumbnail, options: .atomic)
                }
                let imageCount = Self.imageCount(in: images)
                store.updateObject(projectID, objectID) { o in
                    o.status = .ready
                    o.failureReason = nil
                    o.triangleCount = summary.triangles
                    o.vertexCount = summary.vertices
                    o.width = Double(summary.dimensions.x)
                    o.height = Double(summary.dimensions.y)
                    o.depth = Double(summary.dimensions.z)
                    o.imageCount = imageCount
                }
                store.flush()
                try? FileManager.default.removeItem(at: checkpoint)
                self.phase = .finished
            } catch is CancellationError {
                self.session = nil
                self.phase = .idle
            } catch {
                self.session = nil
                let message = error.localizedDescription
                store.updateObject(projectID, objectID) { o in
                    o.status = .failed
                    o.failureReason = message
                }
                self.phase = .failed(message)
            }
        }
    }

    func cancel() {
        session?.cancel()
        task?.cancel()
    }

    static func imageCount(in folder: URL) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { ["heic", "jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }.count
    }

    static func thumbnail(for usdz: URL) async -> Data? {
        let request = QLThumbnailGenerator.Request(fileAt: usdz, size: CGSize(width: 480, height: 480),
                                                   scale: 2, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        return rep.uiImage.jpegData(compressionQuality: 0.85)
    }
}
