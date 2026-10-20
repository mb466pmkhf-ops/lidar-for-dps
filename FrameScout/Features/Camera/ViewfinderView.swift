@preconcurrency import AVFoundation
import CoreMotion
import SwiftUI
import UIKit

/// Director's viewfinder: the frame a chosen cinema lens + sensor would see, drawn as frame
/// lines over the iPhone camera.
///
/// It runs on the phone's fused multi-camera (ultra wide + wide + tele as one device) and
/// drives `videoZoomFactor`, so the system hands over between lenses seamlessly and the
/// frame-line maths only has to track one number. In *Fill* the zoom is set so the cinema
/// frame fills ~90 % of the screen (like a real director's finder); in *Context* the phone
/// stays at its widest so you see what is just outside the frame.
@MainActor
final class ViewfinderModel: NSObject, ObservableObject {
    enum Framing: String, Codable, CaseIterable {
        case fill, context
        var label: String { self == .fill ? "Fill" : "Context" }
    }

    enum MaskStrength: String, Codable, CaseIterable {
        case light, dark, off
        var label: String { rawValue.capitalized }
        var opacity: Double {
            switch self {
            case .light: return 0.5
            case .dark: return 0.85
            case .off: return 0
            }
        }
    }

    /// Persisted between launches so the viewfinder opens on the last lens package.
    struct Settings: Codable, Equatable {
        var rig = CameraRig()
        var squeeze: Double = 1
        var framing: Framing = .fill
        var mask: MaskStrength = .light
        var showLevel = true
        var showThirds = false
        var showSafeArea = false
        var compareNeighbours = false
        /// Multiplies tan(FOV/2) of the phone image; for matching a particular phone exactly.
        var calibration: Double = 1
    }

    static let squeezes: [Double] = [1, 1.25, 1.3, 1.5, 1.65, 1.8, 2]
    static let fillFraction = 0.9
    private static let settingsKey = "viewfinder.settings.v2"

    @Published var settings: Settings { didSet { if settings != oldValue { persist() } } }
    @Published var permissionDenied = false
    @Published var unavailable = false
    @Published private(set) var zoom: Double = 1
    @Published private(set) var minZoom: Double = 1
    @Published private(set) var maxZoom: Double = 1
    /// Long-side field of view of the phone image at zoom 1 (degrees).
    @Published private(set) var baseFOV: Double = 0
    @Published private(set) var isWidescreenFormat = true
    @Published private(set) var phoneLens = ""
    @Published private(set) var focusLocked = false
    @Published private(set) var exposureBias: Float = 0
    @Published private(set) var attitude = ViewfinderMath.Attitude(roll: 0, tilt: 0)
    @Published var lastSavedMessage: String?
    @Published var focusIndicator: CGPoint?

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "framescout.viewfinder")
    private let motion = CMMotionManager()
    private var device: AVCaptureDevice?
    private var zoomObservation: NSKeyValueObservation?
    private var photoDelegate: PhotoCaptureDelegate?
    /// Zoom factor that Apple's camera app calls "1×" (the wide lens).
    private var displayZoomBase: Double = 1
    private var lastImageSize = ViewfinderMath.Size(width: 0, height: 0)
    private var configured = false
    weak var preview: CameraPreviewView?

    override init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = saved
        } else {
            settings = Settings()
        }
        super.init()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    // MARK: Derived optics

    var rig: CameraRig { settings.rig }

    var target: ViewfinderMath.Size {
        ViewfinderMath.targetFOV(focalLength: settings.rig.focalLength, sensor: settings.rig.sensor,
                                 aspect: settings.rig.aspect, squeeze: settings.squeeze)
    }

    /// Calibrated long-side FOV of the phone image at zoom 1.
    var calibratedBaseFOV: Double {
        guard baseFOV > 0 else { return 0 }
        return 2 * atan(tan(baseFOV * .pi / 360) * settings.calibration) * 180 / .pi
    }

    var currentPhoneFOV: Double { ViewfinderMath.effectiveFOV(baseFOV: calibratedBaseFOV, zoom: zoom) }

    func frameRect(for target: ViewfinderMath.Size, in imageRect: CGRect) -> CGRect {
        let size = ViewfinderMath.frameSize(target: target,
                                            image: .init(width: imageRect.width, height: imageRect.height),
                                            phoneFOV: currentPhoneFOV)
        guard size.width > 0 else { return .zero }
        return CGRect(x: imageRect.midX - size.width / 2, y: imageRect.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    func tooWide(imageRect: CGRect) -> Bool {
        guard calibratedBaseFOV > 0, imageRect.width > 0 else { return false }
        return ViewfinderMath.exceedsImage(target: target, image: .init(width: imageRect.width, height: imageRect.height),
                                           baseFOV: calibratedBaseFOV, minZoom: minZoom)
    }

    var displayZoom: Double { zoom / displayZoomBase }

    var lensDescription: String {
        var parts = [Optics.formatFocal(settings.rig.focalLength), settings.rig.sensor.displayName]
        if settings.squeeze > 1 { parts.append(String(format: "%g× anamorphic", settings.squeeze)) }
        if settings.rig.aspect != .sensor { parts.append(settings.rig.aspect.label) }
        return parts.joined(separator: " · ")
    }

    // MARK: Session

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted { self.configure() } else { self.permissionDenied = true }
                }
            }
        default:
            permissionDenied = true
        }
        startMotion()
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        let session = self.session
        queue.async { session.stopRunning() }
    }

    private func configure() {
        guard !configured else {
            let session = self.session
            queue.async { if !session.isRunning { session.startRunning() } }
            return
        }
        configured = true
        let widescreen = ViewfinderMath.prefersWidescreenFormat(target: target)
        let session = self.session
        let photoOutput = self.photoOutput
        queue.async {
            // Fused devices first: they switch lenses inside one stream as the zoom changes.
            let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera,
                                                       .builtInDualCamera, .builtInWideAngleCamera]
            guard let device = types.lazy.compactMap({ AVCaptureDevice.default($0, for: .video, position: .back) }).first,
                  let input = try? AVCaptureDeviceInput(device: device) else {
                Task { @MainActor in self.unavailable = true }
                return
            }
            session.beginConfiguration()
            Self.applyPreset(widescreen, to: session)
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            session.commitConfiguration()

            let fov = Self.measuredFOV(device)
            let minZ = Double(device.minAvailableVideoZoomFactor)
            let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { $0.doubleValue }
            let hasUltraWide = device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
            // Keep digital zoom sensible: up to 4× past the longest optical lens.
            let maxZ = min(Double(device.maxAvailableVideoZoomFactor), (switchOvers.last ?? 1) * 4)
            let isWide = session.sessionPreset == .hd1920x1080
            session.startRunning()

            Task { @MainActor in
                self.device = device
                self.baseFOV = fov
                self.minZoom = minZ
                self.maxZoom = max(minZ, maxZ)
                self.displayZoomBase = hasUltraWide ? (switchOvers.first ?? 1) : 1
                self.isWidescreenFormat = isWide
                self.zoom = Double(device.videoZoomFactor)
                // KVO fires on the camera's queue while the zoom ramps.
                self.zoomObservation = device.observe(\.videoZoomFactor, options: [.new]) { @Sendable [weak self] d, _ in
                    let z = Double(d.videoZoomFactor)
                    Task { @MainActor in self?.zoomChanged(z) }
                }
                self.preview?.attach(device: device)
                self.updatePhoneLens()
                self.updateZoom()
            }
        }
    }

    nonisolated private static func applyPreset(_ widescreen: Bool, to session: AVCaptureSession) {
        let preset: AVCaptureSession.Preset = widescreen ? .hd1920x1080 : .photo
        if session.canSetSessionPreset(preset) { session.sessionPreset = preset }
    }

    /// Horizontal (long-side) FOV of the active format, after distortion correction when it is on
    /// (correction crops the ultra wide slightly).
    nonisolated private static func measuredFOV(_ device: AVCaptureDevice) -> Double {
        let format = device.activeFormat
        var fov = Double(format.videoFieldOfView)
        if device.isGeometricDistortionCorrectionEnabled {
            let corrected = Double(format.geometricDistortionCorrectedVideoFieldOfView)
            if corrected > 1 { fov = corrected }
        }
        return fov
    }

    private func zoomChanged(_ z: Double) {
        zoom = z
        updatePhoneLens()
    }

    private func updatePhoneLens() {
        guard let device else { return }
        let name: String
        switch device.activePrimaryConstituent?.deviceType ?? device.deviceType {
        case .builtInUltraWideCamera: name = "ultra wide"
        case .builtInTelephotoCamera: name = "tele"
        default: name = "wide"
        }
        phoneLens = name
    }

    /// Call when the rig, framing or the preview's image size changes.
    func updateZoom(imageRect: CGRect? = nil) {
        if let imageRect, imageRect.width > 0 {
            lastImageSize = .init(width: imageRect.width, height: imageRect.height)
        }
        guard let device, calibratedBaseFOV > 0 else { return }

        let wantsWidescreen = ViewfinderMath.prefersWidescreenFormat(target: target)
        if wantsWidescreen != isWidescreenFormat {
            switchFormat(widescreen: wantsWidescreen)
            return
        }
        guard lastImageSize.width > 0 else { return }

        var desired = minZoom
        if settings.framing == .fill {
            desired = ViewfinderMath.fillZoom(target: target, image: lastImageSize,
                                              baseFOV: calibratedBaseFOV, fill: Self.fillFraction)
        }
        desired = min(max(desired, minZoom), maxZoom)
        guard abs(desired - Double(device.videoZoomFactor)) / desired > 0.005 else { return }
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.ramp(toVideoZoomFactor: CGFloat(desired), withRate: 24)
            device.unlockForConfiguration()
        }
    }

    private func switchFormat(widescreen: Bool) {
        isWidescreenFormat = widescreen
        guard let device else { return }
        let session = self.session
        queue.async {
            session.beginConfiguration()
            Self.applyPreset(widescreen, to: session)
            session.commitConfiguration()
            let fov = Self.measuredFOV(device)
            let maxAvailable = Double(device.maxAvailableVideoZoomFactor)
            Task { @MainActor in
                self.baseFOV = fov
                self.maxZoom = max(self.minZoom, min(self.maxZoom, maxAvailable))
                // The preview's image rect changes aspect; the next report re-runs updateZoom.
                self.lastImageSize = .init(width: 0, height: 0)
            }
        }
    }

    // MARK: Focus & exposure

    /// Tap: focus and expose on a point, keep following it (continuous AF/AE).
    func focus(atLayerPoint point: CGPoint) {
        guard let device, let preview else { return }
        let devicePoint = preview.previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        focusIndicator = point
        focusLocked = false
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = devicePoint }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = devicePoint }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
            device.unlockForConfiguration()
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self, self.focusIndicator == point, !self.focusLocked else { return }
            self.focusIndicator = nil
        }
    }

    /// AE/AF/AWB lock, so the image stops pumping while you frame up.
    func toggleLock() {
        guard let device else { return }
        let lock = !focusLocked
        focusLocked = lock
        if !lock { focusIndicator = nil }
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if lock {
                if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
                if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
                if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
            } else {
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
            }
            device.unlockForConfiguration()
        }
    }

    func setExposureBias(_ ev: Float) {
        guard let device else { return }
        let clamped = min(max(ev, device.minExposureTargetBias), device.maxExposureTargetBias)
        exposureBias = clamped
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.setExposureTargetBias(clamped, completionHandler: nil)
            device.unlockForConfiguration()
        }
    }

    // MARK: Level

    private func startMotion() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let g = data?.gravity else { return }
            let raw = ViewfinderMath.attitude(gravityX: g.x, gravityY: g.y, gravityZ: g.z)
            // Light smoothing so the level line doesn't shimmer.
            let k = 0.25
            self.attitude = .init(roll: self.attitude.roll + (raw.roll - self.attitude.roll) * k,
                                  tilt: self.attitude.tilt + (raw.tilt - self.attitude.tilt) * k)
        }
    }

    // MARK: Capture

    /// Captures a still, cropped to the frame lines.
    func capture(frameRect: CGRect, imageRect: CGRect, completion: @escaping (Data?) -> Void) {
        let settings = AVCapturePhotoSettings()
        if let angle = preview?.captureRotationAngle, let connection = photoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        let normalized = CGRect(x: (frameRect.minX - imageRect.minX) / imageRect.width,
                                y: (frameRect.minY - imageRect.minY) / imageRect.height,
                                width: frameRect.width / imageRect.width,
                                height: frameRect.height / imageRect.height)
        let delegate = PhotoCaptureDelegate { data in
            let cropped = data.flatMap { ViewfinderModel.crop($0, to: normalized) }
            Task { @MainActor in completion(cropped) }
        }
        photoDelegate = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    nonisolated static func crop(_ data: Data, to normalized: CGRect) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let full = CGRect(origin: .zero, size: size)
        let rect = CGRect(x: normalized.minX * size.width, y: normalized.minY * size.height,
                          width: normalized.width * size.width, height: normalized.height * size.height)
            .intersection(full)
        guard rect.width > 10, rect.height > 10 else { return image.jpegData(compressionQuality: 0.9) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        let out = renderer.image { _ in image.draw(at: CGPoint(x: -rect.minX, y: -rect.minY)) }
        return out.jpegData(compressionQuality: 0.9)
    }
}

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: @Sendable (Data?) -> Void
    /// Called on AVFoundation's queue, so the handler must not assume the main actor.
    init(completion: @escaping @Sendable (Data?) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        completion(error == nil ? photo.fileDataRepresentation() : nil)
    }
}

/// UIKit preview whose image rect (aspect-fit) is reported for frame-line maths.
final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onImageRect: ((CGRect) -> Void)?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var timer: Timer?

    var captureRotationAngle: CGFloat? { rotationCoordinator?.videoRotationAngleForHorizonLevelCapture }

    func attach(device: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        applyRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] c, _ in
            let angle = c.videoRotationAngleForHorizonLevelPreview
            DispatchQueue.main.async { self?.applyRotation(angle) }
        }
    }

    private func applyRotation(_ angle: CGFloat) {
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        reportRect()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        timer?.invalidate()
        guard window != nil else { return }
        // The image rect only becomes valid once frames flow (and changes with the format); poll cheaply.
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.reportRect() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportRect()
    }

    func reportRect() {
        let rect = previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        if rect.width > 1, rect.height > 1 { onImageRect?(rect) }
    }

    deinit { timer?.invalidate() }
}

struct CameraPreview: UIViewRepresentable {
    let model: ViewfinderModel
    @Binding var imageRect: CGRect

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = model.session
        view.previewLayer.videoGravity = .resizeAspect
        view.onImageRect = { rect in
            if rect.integral != imageRect.integral { DispatchQueue.main.async { imageRect = rect } }
        }
        model.preview = view
        return view
    }

    func updateUIView(_ view: CameraPreviewView, context: Context) {}
}

struct ViewfinderView: View {
    let target: CaptureTarget
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ViewfinderModel()
    @State private var imageRect: CGRect = .zero
    @State private var flash = false
    @State private var pinchSteps = 0
    @State private var showCalibration = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                CameraPreview(model: model, imageRect: $imageRect)
                    .ignoresSafeArea()
                frameOverlay
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                gestureLayer
                    .ignoresSafeArea()
                if let p = model.focusIndicator {
                    Rectangle()
                        .stroke(Color.white.opacity(model.focusLocked ? 1 : 0.8), lineWidth: 1)
                        .frame(width: 64, height: 64)
                        .overlay(alignment: .bottom) {
                            if model.focusLocked {
                                Text("AE/AF lock").font(.fsMicro).tracking(Theme.tracking).offset(y: 16)
                            }
                        }
                        .position(p)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                if flash { Color.white.opacity(0.5).ignoresSafeArea().allowsHitTesting(false) }
                VStack(spacing: 0) {
                    topBar
                    readout.padding(.top, 6)
                    Spacer()
                    if !landscape {
                        Text("Turn the phone sideways for full-size frame lines")
                            .font(.fsMicro).tracking(Theme.tracking)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.bottom, 8)
                    }
                    controls
                }
                .padding(.horizontal, landscape ? 20 : 12)
                .padding(.vertical, 8)
                if model.permissionDenied || model.unavailable {
                    RequirementBanner(title: model.permissionDenied ? "Camera access needed" : "No back camera",
                                      message: model.permissionDenied
                                        ? "Allow camera access in Settings › FrameScout to use the lens viewfinder."
                                        : "This device has no usable back camera.",
                                      systemImage: "camera")
                        .padding()
                }
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.settings) { _, _ in model.updateZoom(imageRect: imageRect) }
        .onChange(of: imageRect) { _, rect in model.updateZoom(imageRect: rect) }
        .onChange(of: model.baseFOV) { _, _ in model.updateZoom(imageRect: imageRect) }
        .sheet(isPresented: $showCalibration) {
            ViewfinderCalibrationSheet(calibration: $model.settings.calibration)
                .presentationDetents([.medium])
        }
    }

    // MARK: Overlay

    private var frameRect: CGRect { model.frameRect(for: model.target, in: imageRect) }

    private var frameOverlay: some View {
        Canvas { ctx, size in
            let frame = frameRect
            guard frame.width > 0 else { return }
            let opacity = model.settings.mask.opacity
            if opacity > 0 {
                var mask = Path(CGRect(origin: .zero, size: size))
                mask.addRect(frame)
                ctx.fill(mask, with: .color(.black.opacity(opacity)), style: FillStyle(eoFill: true))
            }
            ctx.stroke(Path(frame), with: .color(.white), lineWidth: 1.5)

            // Centre mark.
            var guides = Path()
            guides.move(to: CGPoint(x: frame.midX - 10, y: frame.midY))
            guides.addLine(to: CGPoint(x: frame.midX + 10, y: frame.midY))
            guides.move(to: CGPoint(x: frame.midX, y: frame.midY - 10))
            guides.addLine(to: CGPoint(x: frame.midX, y: frame.midY + 10))
            if model.settings.showThirds {
                for i in 1...2 {
                    let x = frame.minX + frame.width * CGFloat(i) / 3
                    let y = frame.minY + frame.height * CGFloat(i) / 3
                    guides.move(to: CGPoint(x: x, y: frame.minY)); guides.addLine(to: CGPoint(x: x, y: frame.maxY))
                    guides.move(to: CGPoint(x: frame.minX, y: y)); guides.addLine(to: CGPoint(x: frame.maxX, y: y))
                }
            }
            ctx.stroke(guides, with: .color(.white.opacity(0.45)), lineWidth: 0.75)

            if model.settings.showSafeArea {
                let safe = frame.insetBy(dx: frame.width * 0.05, dy: frame.height * 0.05)
                ctx.stroke(Path(safe), with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 0.75, dash: [4, 4]))
            }

            if model.settings.compareNeighbours {
                let lenses = LensLibrary.commonFocalLengths
                for step in [-1, 1] {
                    let f = ViewfinderMath.steppedFocalLength(from: model.rig.focalLength, by: step, in: lenses)
                    guard abs(f - model.rig.focalLength) > 0.01 else { continue }
                    let t = ViewfinderMath.targetFOV(focalLength: f, sensor: model.rig.sensor,
                                                     aspect: model.rig.aspect, squeeze: model.settings.squeeze)
                    let r = model.frameRect(for: t, in: imageRect)
                    ctx.stroke(Path(r), with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 0.75, dash: [6, 5]))
                    ctx.draw(Text(Optics.formatFocal(f)).font(.fsMono).foregroundColor(.white.opacity(0.75)),
                             at: CGPoint(x: r.minX + 6, y: r.minY + 4), anchor: .topLeading)
                }
            }

            if model.settings.showLevel {
                drawLevel(ctx, in: frame)
            }

            ctx.draw(Text(Optics.formatFocal(model.rig.focalLength)).font(.fsMono).foregroundColor(.white),
                     at: CGPoint(x: frame.minX + 6, y: frame.minY + 5), anchor: .topLeading)
            ctx.draw(Text(model.rig.aspect == .sensor ? "" : model.rig.aspect.label).font(.fsMono).foregroundColor(.white.opacity(0.8)),
                     at: CGPoint(x: frame.maxX - 6, y: frame.minY + 5), anchor: .topTrailing)
        }
    }

    /// Horizon line across the frame: two arms either side of the centre, solid when level.
    private func drawLevel(_ ctx: GraphicsContext, in frame: CGRect) {
        let roll = model.attitude.roll
        let level = abs(roll) < 0.5
        let arm = min(frame.width, frame.height) * 0.28
        let gap: CGFloat = 26
        let angle = CGFloat(-roll * .pi / 180)
        let dx = cos(angle), dy = sin(angle)
        let c = CGPoint(x: frame.midX, y: frame.midY)
        var line = Path()
        line.move(to: CGPoint(x: c.x - dx * (gap + arm), y: c.y - dy * (gap + arm)))
        line.addLine(to: CGPoint(x: c.x - dx * gap, y: c.y - dy * gap))
        line.move(to: CGPoint(x: c.x + dx * gap, y: c.y + dy * gap))
        line.addLine(to: CGPoint(x: c.x + dx * (gap + arm), y: c.y + dy * (gap + arm)))
        ctx.stroke(line, with: .color(.white.opacity(level ? 0.95 : 0.5)), lineWidth: level ? 1.5 : 1)
        // Fixed reference ticks so you can see which way to turn.
        var ticks = Path()
        ticks.move(to: CGPoint(x: c.x - gap - arm - 10, y: c.y)); ticks.addLine(to: CGPoint(x: c.x - gap - arm - 2, y: c.y))
        ticks.move(to: CGPoint(x: c.x + gap + arm + 2, y: c.y)); ticks.addLine(to: CGPoint(x: c.x + gap + arm + 10, y: c.y))
        ctx.stroke(ticks, with: .color(.white.opacity(0.6)), lineWidth: 1)
    }

    private var gestureLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 1, coordinateSpace: .local) { point in model.focus(atLayerPoint: point) }
            .onLongPressGesture(minimumDuration: 0.6) { model.toggleLock() }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        // Pinch out = longer lens, one step per ~18 % of pinch.
                        let steps = Int((log(value.magnification) / log(1.18)).rounded(.towardZero))
                        if steps != pinchSteps {
                            let f = ViewfinderMath.steppedFocalLength(from: model.settings.rig.focalLength, by: steps - pinchSteps)
                            model.settings.rig.focalLength = f
                            pinchSteps = steps
                        }
                    }
                    .onEnded { _ in pinchSteps = 0 }
            )
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(alignment: .center, spacing: 16) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .light)).frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            UnderlineTabs(options: ViewfinderModel.Framing.allCases.map { ($0, $0.label) },
                          selection: $model.settings.framing)
            Spacer()
            Button { model.toggleLock() } label: {
                Text("AE/AF lock")
                    .font(.fsLabel).tracking(Theme.tracking)
                    .foregroundStyle(model.focusLocked ? Color.black : .white)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(model.focusLocked ? Color.white : Color.clear, in: Rectangle())
                    .overlay(Rectangle().stroke(Color.white.opacity(0.5), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            exposureMenu
            settingsMenu
        }
        .foregroundStyle(.white)
    }

    private var exposureMenu: some View {
        Menu {
            ForEach([-2.0, -1.33, -0.67, 0, 0.67, 1.33, 2.0], id: \.self) { ev in
                Button(String(format: "%+.1f EV", ev)) { model.setExposureBias(Float(ev)) }
            }
        } label: {
            Text(String(format: "%+.1f EV", model.exposureBias))
                .font(.fsMono)
                .foregroundStyle(abs(model.exposureBias) > 0.01 ? .white : .white.opacity(0.6))
        }
    }

    private var settingsMenu: some View {
        Menu {
            Picker("Mask", selection: $model.settings.mask) {
                ForEach(ViewfinderModel.MaskStrength.allCases, id: \.self) { Text("Mask · \($0.label)").tag($0) }
            }
            Toggle("Horizon level", isOn: $model.settings.showLevel)
            Toggle("Thirds", isOn: $model.settings.showThirds)
            Toggle("90% safe area", isOn: $model.settings.showSafeArea)
            Toggle("Neighbouring lenses", isOn: $model.settings.compareNeighbours)
            Button("Calibrate field of view…") { showCalibration = true }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 17, weight: .light)).frame(width: 36, height: 36)
        }
    }

    /// One monospaced line of facts, like a camera monitor's status bar.
    private var readout: some View {
        HStack(spacing: 14) {
            Text("H \(Optics.formatAngle(model.target.width))  V \(Optics.formatAngle(model.target.height))")
            Text(String(format: "tilt %+.1f°", model.attitude.tilt))
            Text(String(format: "phone %.1f× %@", model.displayZoom, model.phoneLens))
            Spacer()
            if model.tooWide(imageRect: imageRect) {
                Text("wider than the phone sees — frame cut off")
                    .foregroundStyle(Theme.danger)
            }
            if let msg = model.lastSavedMessage {
                Text(msg)
            }
        }
        .font(.fsMono)
        .foregroundStyle(.white.opacity(0.85))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .shadow(color: .black.opacity(0.9), radius: 2)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewfinderLensStrip(focalLength: $model.settings.rig.focalLength)
            HStack(alignment: .center, spacing: 18) {
                Menu {
                    ForEach(SensorLibrary.manufacturers, id: \.self) { maker in
                        Section(maker.isEmpty ? "Generic" : maker) {
                            ForEach(SensorLibrary.presets.filter { $0.manufacturer == maker }) { s in
                                Button { model.settings.rig.sensorID = s.id } label: {
                                    if s.id == model.rig.sensorID { Label(s.name, systemImage: "checkmark") } else { Text(s.name) }
                                }
                            }
                        }
                    }
                } label: {
                    menuLabel(model.rig.sensor.displayName)
                }
                Menu {
                    Picker("Frame lines", selection: $model.settings.rig.aspect) {
                        ForEach(FrameAspect.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    menuLabel(model.rig.aspect.label)
                }
                Menu {
                    Picker("Squeeze", selection: $model.settings.squeeze) {
                        ForEach(ViewfinderModel.squeezes, id: \.self) { s in
                            Text(s == 1 ? "Spherical" : String(format: "%g× anamorphic", s)).tag(s)
                        }
                    }
                } label: {
                    menuLabel(model.settings.squeeze == 1 ? "Spherical" : String(format: "%g× ana", model.settings.squeeze))
                }
                Spacer(minLength: 0)
                Button(action: captureFrame) {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 58, height: 58)
                        .overlay(Circle().fill(Color.white).padding(5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save frame")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.62), in: Rectangle())
    }

    private func menuLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .light))
        }
        .font(.fsLabel)
        .tracking(Theme.tracking)
        .foregroundStyle(.white)
        .frame(minHeight: 36)
    }

    private func captureFrame() {
        let frame = frameRect.intersection(imageRect)
        guard frame.width > 0 else { return }
        withAnimation(.linear(duration: 0.1)) { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { flash = false }
        let description = model.lensDescription + String(format: " · tilt %+.0f°", model.attitude.tilt)
        model.capture(frameRect: frame, imageRect: imageRect) { data in
            guard let data else { return }
            let ref = target.locationRef ?? viewfinderDropLocation()
            guard let ref else { return }
            store.addPhoto(data, to: ref, source: .viewfinder, caption: description, lensDescription: model.lensDescription)
            model.lastSavedMessage = "saved to \(store.location(ref)?.name ?? "location")"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { model.lastSavedMessage = nil }
        }
    }

    /// Quick viewfinder captures land in a "Viewfinder Frames" location in Quick Scans.
    private func viewfinderDropLocation() -> LocationRef? {
        let pid = store.quickScanProjectID()
        if let existing = store.project(pid)?.locations.first(where: { $0.name == "Viewfinder Frames" }) {
            return LocationRef(projectID: pid, locationID: existing.id)
        }
        return store.addLocation(to: pid, name: "Viewfinder Frames")
    }
}

/// Focal lengths as plain numbers; the chosen one is white and underlined, like the site's nav.
struct ViewfinderLensStrip: View {
    @Binding var focalLength: Double
    @State private var showCustom = false
    @State private var customText = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(LensLibrary.commonFocalLengths, id: \.self) { f in
                        let selected = abs(f - focalLength) < 0.01
                        Button { focalLength = f } label: {
                            Text("\(Int(f))")
                                .font(.system(size: 16, weight: selected ? .regular : .light, design: .monospaced))
                                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.5))
                                .frame(minWidth: 40, minHeight: 34)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(Color.white).frame(width: 22, height: 1).opacity(selected ? 1 : 0)
                                }
                        }
                        .buttonStyle(.plain)
                        .id(f)
                    }
                    let isCustom = !LensLibrary.commonFocalLengths.contains { abs($0 - focalLength) < 0.01 }
                    Button {
                        customText = String(format: "%g", focalLength)
                        showCustom = true
                    } label: {
                        Text(isCustom ? Optics.formatFocal(focalLength) : "mm…")
                            .font(.fsLabel).tracking(Theme.tracking)
                            .foregroundStyle(isCustom ? Color.white : Color.white.opacity(0.5))
                            .padding(.horizontal, 8)
                            .frame(minHeight: 34)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onAppear { proxy.scrollTo(focalLength, anchor: .center) }
            .onChange(of: focalLength) { _, f in withAnimation { proxy.scrollTo(f, anchor: .center) } }
        }
        .alert("Focal length (mm)", isPresented: $showCustom) {
            TextField("mm", text: $customText).keyboardType(.decimalPad)
            Button("Set") {
                if let v = Double(customText.replacingOccurrences(of: ",", with: ".")), v > 1, v < 2000 {
                    focalLength = v
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Fine-tunes the phone's reported field of view against a real camera.
struct ViewfinderCalibrationSheet: View {
    @Binding var calibration: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Calibrate field of view").font(.fsHeadline).tracking(0.4)
            Text("The frame lines come from the field of view the phone reports for its cameras, which is usually within 1–2 %. To match a particular camera exactly: set the same lens and sensor here, frame the same edge (a door frame works) on both, then nudge until the lines agree.")
                .font(.fsBody)
                .foregroundStyle(Theme.textSecondary)
            HStack {
                Text("tighter").font(.fsMicro).foregroundStyle(Theme.textTertiary)
                Slider(value: $calibration, in: 0.92...1.08, step: 0.0025)
                Text("wider").font(.fsMicro).foregroundStyle(Theme.textTertiary)
            }
            HStack {
                Text(String(format: "%+.2f %%", (calibration - 1) * 100)).font(.fsMono)
                Spacer()
                Button("Reset") { calibration = 1 }.font(.fsButton)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
    }
}
