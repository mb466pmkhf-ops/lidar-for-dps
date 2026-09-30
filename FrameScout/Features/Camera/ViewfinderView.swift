@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Director's-viewfinder: shows the frame a chosen cinema lens + sensor would see, drawn as
/// frame lines over the iPhone camera. Picks the phone lens (ultra-wide / wide / tele) whose
/// field of view best contains the target, so wide cinema lenses still fit on screen.
@MainActor
final class ViewfinderModel: NSObject, ObservableObject {
    struct PhoneLens: Identifiable {
        let id: String
        let device: AVCaptureDevice
        let name: String
        /// Horizontal (long side) FOV of the active format, degrees.
        let fov: Double
        /// Short/long side ratio of the active format.
        let aspect: Double

        var shortFOV: Double { 2 * atan(tan(fov * .pi / 360) * aspect) * 180 / .pi }
    }

    @Published var rig = CameraRig()
    @Published var lenses: [PhoneLens] = []
    @Published var activeLens: PhoneLens?
    @Published var autoLens = true
    @Published var permissionDenied = false
    @Published var compareNeighbours = false
    @Published var lastSavedMessage: String?

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "framescout.viewfinder")
    private var input: AVCaptureDeviceInput?
    private var photoDelegate: PhotoCaptureDelegate?
    weak var preview: CameraPreviewView?

    /// Whether the chosen lens is wider than any phone camera (frame lines will be clipped).
    var tooWide: Bool {
        guard let lens = activeLens else { return false }
        return rig.horizontalFOV > lens.fov + 0.5 || rig.verticalFOV > lens.shortFOV + 0.5
    }

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
    }

    func stop() {
        let session = self.session
        queue.async { session.stopRunning() }
    }

    private func configure() {
        let types: [(AVCaptureDevice.DeviceType, String)] = [
            (.builtInUltraWideCamera, "0.5× Ultra Wide"),
            (.builtInWideAngleCamera, "1× Wide"),
            (.builtInTelephotoCamera, "Tele"),
        ]
        let session = self.session
        let photoOutput = self.photoOutput
        queue.async {
            var found: [PhoneLens] = []
            session.beginConfiguration()
            session.sessionPreset = .photo
            for (type, name) in types {
                guard let device = AVCaptureDevice.default(type, for: .video, position: .back) else { continue }
                let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
                let long = Double(max(dims.width, dims.height)), short = Double(min(dims.width, dims.height))
                found.append(PhoneLens(id: device.uniqueID, device: device, name: name,
                                       fov: Double(device.activeFormat.videoFieldOfView),
                                       aspect: long > 0 ? short / long : 0.75))
            }
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            session.commitConfiguration()
            Task { @MainActor in
                self.lenses = found.sorted { $0.fov > $1.fov }
                self.chooseLens()
                let s = self.session
                self.queue.async { s.startRunning() }
            }
        }
    }

    /// Narrowest phone camera that still contains the target frame (best resolution).
    func chooseLens() {
        guard autoLens || activeLens == nil else { return }
        let targetH = rig.horizontalFOV * 1.04, targetV = rig.verticalFOV * 1.04
        let fitting = lenses.filter { $0.fov >= targetH && $0.shortFOV >= targetV }
        let best = fitting.min(by: { $0.fov < $1.fov }) ?? lenses.first
        if let best, best.id != activeLens?.id { select(best) }
    }

    func select(_ lens: PhoneLens) {
        activeLens = lens
        let session = self.session
        let current = input
        queue.async {
            session.beginConfiguration()
            if let current { session.removeInput(current) }
            var added: AVCaptureDeviceInput?
            if let newInput = try? AVCaptureDeviceInput(device: lens.device), session.canAddInput(newInput) {
                session.addInput(newInput)
                added = newInput
            }
            session.commitConfiguration()
            // The active format (and so the true FOV) is only settled once the device is in the
            // session with the .photo preset; re-read it for accurate frame lines.
            let dims = CMVideoFormatDescriptionGetDimensions(lens.device.activeFormat.formatDescription)
            let long = Double(max(dims.width, dims.height)), short = Double(min(dims.width, dims.height))
            let measured = PhoneLens(id: lens.id, device: lens.device, name: lens.name,
                                     fov: Double(lens.device.activeFormat.videoFieldOfView),
                                     aspect: long > 0 ? short / long : lens.aspect)
            Task { @MainActor in
                if let added { self.input = added }
                self.activeLens = measured
                if let i = self.lenses.firstIndex(where: { $0.id == measured.id }) { self.lenses[i] = measured }
                self.preview?.attach(device: lens.device)
            }
        }
    }

    var lensDescription: String {
        "\(Optics.formatFocal(rig.focalLength)) · \(rig.sensor.displayName)\(rig.aspect == .sensor ? "" : " · \(rig.aspect.label)")"
    }

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
            DispatchQueue.main.async { completion(cropped) }
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
    private let completion: (Data?) -> Void
    init(completion: @escaping (Data?) -> Void) { self.completion = completion }

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
        // The image rect only becomes valid once frames flow; poll cheaply.
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
            if rect != imageRect { DispatchQueue.main.async { imageRect = rect } }
        }
        model.preview = view
        if let lens = model.activeLens { view.attach(device: lens.device) }
        return view
    }

    func updateUIView(_ view: CameraPreviewView, context: Context) {}
}

/// Frame lines in view coordinates, derived from focal lengths in pixels.
enum FrameLineMath {
    static func frameRect(for rig: CameraRig, imageRect: CGRect, deviceFOV: Double) -> CGRect {
        guard imageRect.width > 0, deviceFOV > 0 else { return .zero }
        let longSide = max(imageRect.width, imageRect.height)
        let fPixels = longSide / (2 * tan(deviceFOV * .pi / 360))
        let w = 2 * fPixels * tan(rig.horizontalFOV * .pi / 360)
        let h = 2 * fPixels * tan(rig.verticalFOV * .pi / 360)
        return CGRect(x: imageRect.midX - w / 2, y: imageRect.midY - h / 2, width: w, height: h)
    }
}

struct ViewfinderView: View {
    let target: CaptureTarget
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ViewfinderModel()
    @State private var imageRect: CGRect = .zero
    @State private var flash = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                CameraPreview(model: model, imageRect: $imageRect)
                    .ignoresSafeArea()
                frameOverlay
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                if flash { Color.white.opacity(0.6).ignoresSafeArea().allowsHitTesting(false) }
                VStack(spacing: 10) {
                    topBar
                    Spacer()
                    controls(isLandscape: geo.size.width > geo.size.height)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                if model.permissionDenied {
                    RequirementBanner(title: "Camera access needed",
                                      message: "Allow camera access in Settings › FrameScout to use the lens viewfinder.",
                                      systemImage: "camera")
                        .padding()
                }
            }
        }
        .statusBarHidden()
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.rig) { _, _ in model.chooseLens() }
        .onChange(of: model.autoLens) { _, _ in model.chooseLens() }
    }

    private var frameRect: CGRect {
        FrameLineMath.frameRect(for: model.rig, imageRect: imageRect, deviceFOV: model.activeLens?.fov ?? 0)
    }

    private var frameOverlay: some View {
        Canvas { ctx, size in
            let frame = frameRect
            guard frame.width > 0 else { return }
            var mask = Path(CGRect(origin: .zero, size: size))
            mask.addRect(frame)
            ctx.fill(mask, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
            ctx.stroke(Path(frame), with: .color(Theme.accent), lineWidth: 2)
            // Centre cross and thirds.
            var guides = Path()
            guides.move(to: CGPoint(x: frame.midX - 12, y: frame.midY))
            guides.addLine(to: CGPoint(x: frame.midX + 12, y: frame.midY))
            guides.move(to: CGPoint(x: frame.midX, y: frame.midY - 12))
            guides.addLine(to: CGPoint(x: frame.midX, y: frame.midY + 12))
            for i in 1...2 {
                let x = frame.minX + frame.width * CGFloat(i) / 3
                let y = frame.minY + frame.height * CGFloat(i) / 3
                guides.move(to: CGPoint(x: x, y: frame.minY)); guides.addLine(to: CGPoint(x: x, y: frame.maxY))
                guides.move(to: CGPoint(x: frame.minX, y: y)); guides.addLine(to: CGPoint(x: frame.maxX, y: y))
            }
            ctx.stroke(guides, with: .color(.white.opacity(0.35)), lineWidth: 1)

            if model.compareNeighbours, let lens = model.activeLens {
                let lenses = LensLibrary.commonFocalLengths
                let idx = lenses.firstIndex { $0 >= model.rig.focalLength - 0.01 } ?? 0
                for neighbour in [idx - 1, idx + 1] where lenses.indices.contains(neighbour) {
                    var rig = model.rig
                    rig.focalLength = lenses[neighbour]
                    let r = FrameLineMath.frameRect(for: rig, imageRect: imageRect, deviceFOV: lens.fov)
                    ctx.stroke(Path(r), with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    ctx.draw(Text("\(Int(lenses[neighbour]))").font(.caption2.bold()).foregroundColor(.white.opacity(0.8)),
                             at: CGPoint(x: r.minX + 14, y: r.minY + 10))
                }
            }

            ctx.draw(Text("\(Optics.formatFocal(model.rig.focalLength))  H \(Optics.formatAngle(model.rig.horizontalFOV))  V \(Optics.formatAngle(model.rig.verticalFOV))")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundColor(Theme.accent),
                     at: CGPoint(x: frame.minX + 6, y: max(12, frame.minY - 12)), anchor: .leading)
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            OverlayButton(systemImage: "xmark", size: 44) { dismiss() }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Menu {
                    Toggle("Auto phone lens", isOn: $model.autoLens)
                    ForEach(model.lenses) { lens in
                        Button("\(lens.name) · \(Optics.formatAngle(lens.fov))") {
                            model.autoLens = false
                            model.select(lens)
                        }
                    }
                    Toggle("Show neighbouring lenses", isOn: $model.compareNeighbours)
                } label: {
                    Label(model.activeLens.map { "\($0.name)\(model.autoLens ? " · auto" : "")" } ?? "Camera", systemImage: "camera.aperture")
                        .font(.caption.bold())
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                if model.tooWide {
                    Text("Wider than the phone's widest camera — frame lines exceed the image")
                        .font(.caption2)
                        .padding(6)
                        .background(Theme.danger.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                }
                if let msg = model.lastSavedMessage {
                    Text(msg).font(.caption2.bold()).padding(6).background(Theme.success, in: Capsule()).foregroundStyle(.black)
                }
            }
        }
    }

    private func controls(isLandscape: Bool) -> some View {
        VStack(spacing: 10) {
            LensPicker(focalLength: $model.rig.focalLength)
            HStack(spacing: 10) {
                SensorPicker(sensorID: $model.rig.sensorID, customSensor: $model.rig.customSensor)
                    .frame(maxWidth: 320)
                Menu {
                    Picker("Frame lines", selection: $model.rig.aspect) {
                        ForEach(FrameAspect.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Text(model.rig.aspect.label)
                        .font(.system(size: 15, weight: .bold))
                        .frame(minWidth: 56, minHeight: 44)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
                }
                Spacer(minLength: 0)
                OverlayButton(systemImage: "camera.fill", tint: Theme.accent, filled: true, size: 64) { captureFrame() }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func captureFrame() {
        let frame = frameRect.intersection(imageRect)
        guard frame.width > 0 else { return }
        withAnimation(.linear(duration: 0.1)) { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { flash = false }
        let description = model.lensDescription
        model.capture(frameRect: frame, imageRect: imageRect) { data in
            guard let data else { return }
            let ref = target.locationRef ?? viewfinderDropLocation()
            guard let ref else { return }
            store.addPhoto(data, to: ref, source: .viewfinder, caption: description, lensDescription: description)
            model.lastSavedMessage = "Frame saved to \(store.location(ref)?.name ?? "location")"
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
