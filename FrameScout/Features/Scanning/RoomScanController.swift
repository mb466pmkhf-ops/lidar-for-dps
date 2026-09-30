import ARKit
import RoomPlan
import SwiftUI
import UIKit

/// Drives a RoomPlan capture. Pause/resume is implemented the way Apple supports it:
/// "pause" stops the current room segment while keeping the AR session (and its coordinate
/// space) alive; "resume" starts a new segment. Segments are merged with `StructureBuilder`
/// on finish, which also makes multi-room houses and corridors possible.
@MainActor
final class RoomScanModel: ObservableObject {
    @Published var phase: ScanPhase = .ready
    @Published var info = LiveScanInfo()
    @Published var instruction: String?
    @Published var photos: [PendingPhoto] = []
    @Published var result: ScanResult?

    fileprivate weak var controller: RoomScanViewController?
    private var segments: [CapturedRoom] = []
    private var liveRoom: CapturedRoom?
    private var finishWhenProcessed = false
    private var startDate: Date?
    private var accumulated: TimeInterval = 0
    private var clock: Timer?

    var canPause: Bool { phase == .scanning }
    var canResume: Bool { phase == .paused }
    var canFinish: Bool { phase == .scanning || phase == .paused }

    func pause() { controller?.stopSegment(pauseAR: false) }
    func resume() { controller?.startSegment() }

    func finish() {
        switch phase {
        case .scanning:
            finishWhenProcessed = true
            controller?.stopSegment(pauseAR: true)
        case .paused:
            controller?.shutdownAR()
            Task { await finalize() }
        default:
            break
        }
    }

    func cancel() { controller?.shutdownAR() }

    func snapPhoto() {
        guard let frame = controller?.currentFrame, let photo = FrameGrabber.pendingPhoto(from: frame) else { return }
        photos.append(photo)
    }

    var northOffset: Double? { controller?.heading.northOffset }

    // MARK: Callbacks from the view controller

    fileprivate func segmentStarted() {
        phase = .scanning
        instruction = nil
        startDate = Date()
        clock?.invalidate()
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let startDate else { return }
        info.elapsed = accumulated + Date().timeIntervalSince(startDate)
        info.northOffset = controller?.heading.northOffset
    }

    fileprivate func segmentStopping() {
        if let startDate { accumulated += Date().timeIntervalSince(startDate) }
        startDate = nil
        clock?.invalidate()
        phase = .processing
        // Safety net: RoomPlan normally presents a result within a few seconds.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, self.phase == .processing else { return }
            self.segmentProcessed(nil, error: nil)
        }
    }

    fileprivate func liveUpdate(_ room: CapturedRoom) {
        liveRoom = room
        refreshStats()
    }

    fileprivate func segmentProcessed(_ room: CapturedRoom?, error: Error?) {
        guard phase == .processing || phase == .scanning else { return }
        liveRoom = nil
        if let room {
            segments.append(room)
        }
        refreshStats()
        if segments.isEmpty {
            let reason = error.map { ": \($0.localizedDescription)" } ?? ""
            phase = .failed("RoomPlan could not process this capture\(reason). Scan more slowly and keep walls and floor edges in view.")
            return
        }
        if finishWhenProcessed {
            Task { await finalize() }
        } else {
            phase = .paused
        }
    }

    fileprivate func setInstruction(_ instruction: RoomCaptureSession.Instruction) {
        switch instruction {
        case .normal: self.instruction = nil
        case .moveCloseToWall: self.instruction = "Move closer to the wall"
        case .moveAwayFromWall: self.instruction = "Move away from the wall"
        case .slowDown: self.instruction = "Slow down"
        case .turnOnLight: self.instruction = "More light needed"
        case .lowTexture: self.instruction = "Low texture — aim at edges and furniture"
        @unknown default: self.instruction = nil
        }
    }

    private func refreshStats() {
        var rooms = segments
        if let liveRoom { rooms.append(liveRoom) }
        guard !rooms.isEmpty else { return }
        let elements = RoomElements(rooms: rooms)
        let plan = RoomPlanConverter.floorPlan(elements)
        info.stats = RoomPlanConverter.stats(elements, plan: plan)
        info.segments = segments.count + (liveRoom == nil ? 0 : 1)
    }

    private func finalize() async {
        phase = .finalizing
        guard !segments.isEmpty else {
            phase = .failed("Nothing was captured. Point the camera at the walls and move slowly around the space.")
            return
        }
        var structure: CapturedStructure?
        if segments.count > 1 {
            do {
                structure = try await StructureBuilder(options: [.beautifyObjects]).capturedStructure(from: segments)
            } catch {
                // Segments already share one coordinate space, so they remain usable unmerged.
                structure = nil
            }
        }
        info.northOffset = controller?.heading.northOffset
        result = .room(rooms: segments, structure: structure)
        phase = .finished
    }

    var segmentCount: Int { segments.count }
}

final class RoomScanViewController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    private let model: RoomScanModel
    private var captureView: RoomCaptureView!
    private let configuration = RoomCaptureSession.Configuration()
    let heading = HeadingEstimator()
    private var headingTimer: Timer?
    private var didStart = false
    private var arStopped = false

    init(model: RoomScanModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var currentFrame: ARFrame? { captureView?.captureSession.arSession.currentFrame }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        captureView = RoomCaptureView(frame: view.bounds)
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        captureView.captureSession.delegate = self
        captureView.delegate = self
        view.addSubview(captureView)
        model.controller = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        guard !didStart else { return }
        didStart = true
        heading.start()
        headingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let frame = self.currentFrame else { return }
            self.heading.sample(frame: frame)
        }
        startSegment()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        shutdownAR()
    }

    func startSegment() {
        arStopped = false
        captureView.captureSession.run(configuration: configuration)
        model.segmentStarted()
    }

    func stopSegment(pauseAR: Bool) {
        model.segmentStopping()
        captureView.captureSession.stop(pauseARSession: pauseAR)
        if pauseAR { stopSensors() }
    }

    func shutdownAR() {
        guard !arStopped else { return }
        arStopped = true
        stopSensors()
        if model.phase == .scanning {
            captureView?.captureSession.stop()
        } else {
            captureView?.captureSession.arSession.pause()
        }
    }

    private func stopSensors() {
        headingTimer?.invalidate()
        headingTimer = nil
        heading.stop()
    }

    // MARK: RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        let model = self.model
        let usable = error == nil || !processedResult.walls.isEmpty
        Task { @MainActor in model.segmentProcessed(usable ? processedResult : nil, error: error) }
    }

    // MARK: RoomCaptureSessionDelegate

    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        let model = self.model
        Task { @MainActor in model.liveUpdate(room) }
    }

    func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
        let model = self.model
        Task { @MainActor in model.setInstruction(instruction) }
    }

}

struct RoomCaptureContainer: UIViewControllerRepresentable {
    let model: RoomScanModel

    func makeUIViewController(context: Context) -> RoomScanViewController {
        RoomScanViewController(model: model)
    }

    func updateUIViewController(_ controller: RoomScanViewController, context: Context) {}
}
