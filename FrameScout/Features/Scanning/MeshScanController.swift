import ARKit
import RealityKit
import SwiftUI
import UIKit

/// Raw LiDAR scene-reconstruction capture: works outdoors, in irregular spaces and anywhere
/// RoomPlan's room model doesn't fit (exteriors, alleys, stages, vehicles…).
@MainActor
final class MeshScanModel: ObservableObject {
    @Published var phase: ScanPhase = .ready
    @Published var info = LiveScanInfo()
    @Published var trackingMessage: String?
    @Published var photos: [PendingPhoto] = []
    @Published var result: ScanResult?

    fileprivate weak var controller: MeshScanViewController?
    private var startDate: Date?
    private var accumulated: TimeInterval = 0

    var canPause: Bool { phase == .scanning }
    var canResume: Bool { phase == .paused }
    var canFinish: Bool { phase == .scanning || phase == .paused }
    var northOffset: Double? { controller?.heading.northOffset }

    func pause() {
        guard phase == .scanning else { return }
        controller?.pauseSession()
        if let startDate { accumulated += Date().timeIntervalSince(startDate) }
        startDate = nil
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        controller?.resumeSession()
        startDate = Date()
        phase = .scanning
    }

    func finish() {
        guard canFinish, let controller else { return }
        phase = .finalizing
        let anchors = controller.meshAnchors
        controller.pauseSession()
        info.northOffset = controller.heading.northOffset
        Task.detached(priority: .userInitiated) {
            let mesh = MeshExtractor.extract(anchors)
            await MainActor.run {
                if mesh.isEmpty {
                    self.phase = .failed("No LiDAR surfaces were captured. Move slowly and keep surfaces within about 5 m.")
                } else {
                    self.result = .mesh(mesh)
                    self.phase = .finished
                }
            }
        }
    }

    func cancel() { controller?.pauseSession() }

    func snapPhoto() {
        guard let frame = controller?.currentFrame, let photo = FrameGrabber.pendingPhoto(from: frame) else { return }
        photos.append(photo)
    }

    fileprivate func started() {
        startDate = Date()
        phase = .scanning
    }

    fileprivate func tick(stats: ScanStats?) {
        if let startDate { info.elapsed = accumulated + Date().timeIntervalSince(startDate) }
        if let stats { info.stats = stats }
        info.northOffset = controller?.heading.northOffset
    }
}

final class MeshScanViewController: UIViewController, ARSessionDelegate {
    private let model: MeshScanModel
    private var arView: ARView!
    private let configuration: ARWorldTrackingConfiguration = {
        let c = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            c.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            c.sceneReconstruction = .mesh
        }
        c.planeDetection = [.horizontal]
        c.environmentTexturing = .none
        return c
    }()
    let heading = HeadingEstimator()
    private var timer: Timer?
    private var analysing = false
    private var didStart = false

    init(model: MeshScanModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var currentFrame: ARFrame? { arView?.session.currentFrame }

    var meshAnchors: [ARMeshAnchor] {
        arView?.session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        arView = ARView(frame: view.bounds, cameraMode: .ar, automaticallyConfigureSession: false)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Live LiDAR mesh overlay so the operator sees exactly what has been captured.
        arView.debugOptions.insert(.showSceneUnderstanding)
        arView.renderOptions.insert(.disableMotionBlur)
        arView.session.delegate = self
        view.addSubview(arView)
        model.controller = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        guard !didStart else { return }
        didStart = true
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        heading.start()
        model.started()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.periodicUpdate()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        timer?.invalidate()
        heading.stop()
        arView.session.pause()
    }

    func pauseSession() { arView.session.pause() }

    /// Running again without reset keeps the existing mesh anchors and relocalises.
    func resumeSession() { arView.session.run(configuration) }

    private var tickCount = 0

    private func periodicUpdate() {
        guard let frame = currentFrame else { return }
        heading.sample(frame: frame)
        tickCount += 1
        let model = self.model
        guard tickCount % 5 == 0, !analysing, model.phase == .scanning else {
            Task { @MainActor in model.tick(stats: nil) }
            return
        }
        analysing = true
        let anchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let stats = MeshExtractor.extract(anchors).analyse(cellSize: 0.2).stats
            DispatchQueue.main.async {
                self?.analysing = false
                Task { @MainActor in model.tick(stats: stats) }
            }
        }
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let message: String?
        switch camera.trackingState {
        case .normal: message = nil
        case .notAvailable: message = "Tracking unavailable"
        case .limited(let reason):
            switch reason {
            case .excessiveMotion: message = "Slow down"
            case .insufficientFeatures: message = "Not enough detail — aim at textured surfaces"
            case .initializing: message = "Initialising — move the phone slowly"
            case .relocalizing: message = "Relocalising — return to where you paused"
            @unknown default: message = "Tracking limited"
            }
        }
        let model = self.model
        Task { @MainActor in model.trackingMessage = message }
    }
}

struct MeshCaptureContainer: UIViewControllerRepresentable {
    let model: MeshScanModel

    func makeUIViewController(context: Context) -> MeshScanViewController {
        MeshScanViewController(model: model)
    }

    func updateUIViewController(_ controller: MeshScanViewController, context: Context) {}
}
