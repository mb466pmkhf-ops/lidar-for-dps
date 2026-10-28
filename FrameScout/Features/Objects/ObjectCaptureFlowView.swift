import RealityKit
import SwiftUI

/// Drives Apple's guided Object Capture (iOS 17, LiDAR): find the object, size the box,
/// walk around it in passes (flipping it between passes to get the underside), then build
/// the model on the phone.
@MainActor
final class ObjectCaptureModel: ObservableObject {
    enum Step: Equatable {
        case intro
        case starting
        case ready
        case detecting
        case capturing
        case finishing
        case building
        case failed(String)
    }

    @Published var step: Step = .intro
    @Published private(set) var session: ObjectCaptureSession?
    @Published private(set) var feedback: [String] = []
    /// Shown when a button didn't take (e.g. no object found to box yet).
    @Published var hint: String?
    @Published private(set) var shots = 0
    @Published private(set) var maxShots = 0
    @Published private(set) var passCompleted = false
    @Published private(set) var passes = 1
    private(set) var projectID: UUID?
    private(set) var objectID: UUID?
    private var tasks: [Task<Void, Never>] = []

    static var isSupported: Bool { ObjectCaptureSession.isSupported }

    func begin(store: ProjectStore, projectID: UUID, name: String) {
        guard Self.isSupported else {
            step = .failed("Object Capture needs a LiDAR iPhone or iPad Pro on iOS 17 or later.")
            return
        }
        guard let object = store.addObject(to: projectID, name: name) else { return }
        self.projectID = projectID
        objectID = object.id
        let images = StoragePaths.objectFile(projectID, objectID: object.id, .images)
        let checkpoint = StoragePaths.objectFile(projectID, objectID: object.id, .checkpoint)
        StoragePaths.ensureDirectory(images)
        StoragePaths.ensureDirectory(checkpoint)

        let session = ObjectCaptureSession()
        var configuration = ObjectCaptureSession.Configuration()
        configuration.checkpointDirectory = checkpoint
        session.start(imagesDirectory: images, configuration: configuration)
        self.session = session
        step = .starting
        UIApplication.shared.isIdleTimerDisabled = true

        tasks.append(Task { [weak self] in
            for await state in session.stateUpdates {
                self?.handle(state)
            }
        })
        tasks.append(Task { [weak self] in
            for await set in session.feedbackUpdates {
                self?.feedback = Self.prioritized(set)
            }
        })
        // Counters are plain properties on the session; sample them a few times a second.
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let s = self.session else { return }
                self.shots = s.numberOfShotsTaken
                self.maxShots = s.maximumNumberOfInputImages
                if s.userCompletedScanPass != self.passCompleted { self.passCompleted = s.userCompletedScanPass }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        })
    }

    private func handle(_ state: ObjectCaptureSession.CaptureState) {
        switch state {
        case .initializing: step = .starting
        case .ready: step = .ready
        case .detecting: step = .detecting; hint = nil
        case .capturing: step = .capturing
        case .finishing: step = .finishing
        case .completed:
            // The capture session must be released before reconstruction starts (memory).
            stopListening()
            session = nil
            step = .building
        case .failed(let error):
            stopListening()
            session = nil
            step = .failed(error.localizedDescription)
        @unknown default:
            break
        }
    }

    /// Apple's session only moves on once it has found something to box. If it can't, say so
    /// rather than leaving the button looking dead next to a light warning.
    func continueFromReady() {
        guard let session else { return }
        if session.startDetecting() {
            hint = nil
        } else {
            hint = "No object found yet. Aim the centre dot at the object from about 30–60 cm and try again."
        }
    }
    func resetBox() { session?.resetDetection() }
    func startCapturing() { session?.startCapturing() }

    func nextPass(flipped: Bool) {
        guard let session else { return }
        if flipped { session.beginNewScanPassAfterFlip() } else { session.beginNewScanPass() }
        passes += 1
        passCompleted = false
    }

    func finish(store: ProjectStore) {
        if let projectID, let objectID {
            let count = passes
            store.updateObject(projectID, objectID) { $0.scanPasses = count }
        }
        session?.finish()
    }

    /// Abandons the capture and removes the half-made object.
    func discard(store: ProjectStore) {
        session?.cancel()
        stopListening()
        session = nil
        if let projectID, let objectID { store.deleteObject(projectID, objectID) }
        objectID = nil
    }

    private func stopListening() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Actionable messages first; low light is advice, not a blocker, so it goes last.
    nonisolated private static func prioritized(_ set: Set<ObjectCaptureSession.Feedback>) -> [String] {
        let order: [ObjectCaptureSession.Feedback] = [.environmentTooDark, .objectNotDetected, .outOfFieldOfView,
                                                      .objectTooFar, .objectTooClose, .movingTooFast,
                                                      .objectNotFlippable, .overCapturing, .environmentLowLight]
        let known = order.filter(set.contains).compactMap(message(for:))
        let rest = set.filter { !order.contains($0) }.compactMap(message(for:)).sorted()
        return known + rest
    }

    nonisolated private static func message(for feedback: ObjectCaptureSession.Feedback) -> String? {
        switch feedback {
        case .objectTooClose: return "Move further away"
        case .objectTooFar: return "Move closer"
        case .movingTooFast: return "Slow down"
        case .environmentLowLight: return "Light is a bit low — you can still scan; brighter gives more detail"
        case .environmentTooDark: return "Too dark to capture"
        case .outOfFieldOfView: return "Keep the object in view"
        case .objectNotFlippable: return "This object can't be flipped — scan again without flipping"
        case .overCapturing: return "Enough shots here — keep moving round"
        case .objectNotDetected: return "Object not found"
        @unknown default: return nil
        }
    }
}

struct ObjectCaptureFlowView: View {
    let projectID: UUID?
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ObjectCaptureModel()
    @StateObject private var builder = ObjectReconstructor()
    @State private var name = ""
    @State private var confirmDiscard = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch model.step {
            case .intro:
                intro
            case .building:
                ObjectBuildProgressView(builder: builder, onOpen: openObject, onLater: closeKeepingImages)
                    .onAppear(perform: startBuild)
            case .failed(let message):
                failure(message)
            default:
                capture
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(model.step != .intro)
        .confirmationDialog("Discard this object scan?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                model.discard(store: store)
                dismiss()
            }
        }
    }

    private var targetProjectID: UUID { projectID ?? store.quickScanProjectID() }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Close") { dismiss() }.font(.fsButton)
                Spacer()
            }
            .padding(.bottom, 28)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Object scan").font(.fsTitle)
                        Text("A photo-textured 3D model of a single object — a prop, a toy, a camera body — ready for Unreal, Blender or AR.")
                            .font(.fsBody).foregroundStyle(Theme.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name").font(.fsLabel).tracking(Theme.tracking).foregroundStyle(Theme.textTertiary)
                        TextField("e.g. Hero teddy, Alexa Mini", text: $name)
                            .font(.poppins(.light, 20))
                            .textInputAutocapitalization(.words)
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Before you start")
                        tip("01", "Put the object on a plain, non-reflective surface with space to walk all the way round it.")
                        tip("02", "Even, bright light; no hard shadows. Matte things scan best — glass, chrome and very shiny or thin parts don't.")
                        tip("03", "Walk slowly round it at one height, then a second lap lower or higher.")
                        tip("04", "If it's rigid, flip it on its side for another pass so the bottom is captured too.")
                        tip("05", "Building the model happens on the phone and takes a few minutes. Keep FrameScout open.")
                    }
                    if !ObjectCaptureModel.isSupported {
                        RequirementBanner(title: "Needs LiDAR and iOS 17",
                                          message: "Object Capture runs on iPhone 12 Pro and later Pro models, and iPad Pro with LiDAR.",
                                          systemImage: "sensor.tag.radiowaves.forward")
                    }
                }
            }
            Button {
                model.begin(store: store, projectID: targetProjectID, name: name)
            } label: {
                Text("Start scanning")
                    .font(.fsButton).tracking(Theme.tracking)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.white, in: Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!ObjectCaptureModel.isSupported)
            .opacity(ObjectCaptureModel.isSupported ? 1 : 0.35)
        }
        .padding(20)
    }

    private func tip(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(number).font(.fsMono).foregroundStyle(Theme.textTertiary)
            Text(text).font(.fsBody).foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Capture

    private var capture: some View {
        ZStack {
            if let session = model.session {
                ObjectCaptureView(session: session)
                    .ignoresSafeArea()
                    .id(ObjectIdentifier(session))
            }
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Button { confirmDiscard = true } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .light)).frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("pass \(model.passes)").font(.fsMono)
                        if model.maxShots > 0 {
                            Text("\(model.shots) / \(model.maxShots) shots").font(.fsMono)
                        }
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 2)
                }
                if let line = model.hint ?? model.feedback.first {
                    Text(line)
                        .font(.fsCaption).tracking(Theme.tracking)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.black.opacity(0.6), in: Rectangle())
                        .padding(.top, 8)
                }
                Spacer()
                bottomPanel
            }
            .padding(16)
            if model.passCompleted && model.step == .capturing {
                passComplete
            }
        }
    }

    private var instruction: String {
        switch model.step {
        case .starting: return "Starting camera…"
        case .ready: return "Point at the object so it sits in the middle of the frame."
        case .detecting: return "Drag the box edges so it just contains the object."
        case .capturing: return "Walk slowly round the object. Shots are taken automatically."
        case .finishing: return "Saving images…"
        default: return ""
        }
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(instruction).font(.fsBody).foregroundStyle(.white)
            HStack(spacing: 10) {
                switch model.step {
                case .ready:
                    primary("Continue") { model.continueFromReady() }
                case .detecting:
                    secondary("Reset box") { model.resetBox() }
                    primary("Start capture") { model.startCapturing() }
                case .capturing:
                    secondary("Finish now") { model.finish(store: store) }
                        .disabled(model.shots < 20)
                        .opacity(model.shots < 20 ? 0.4 : 1)
                default:
                    ProgressView().tint(.white)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.62), in: Rectangle())
    }

    private var passComplete: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pass \(model.passes) complete").font(.fsTitle)
            if let session = model.session {
                ObjectCapturePointCloudView(session: session)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
            }
            Text(model.passes < 3
                 ? "Three passes give the best result: two laps at different heights, then one with the object flipped."
                 : "That's plenty of coverage. Build the model, or add another pass for detail.")
                .font(.fsBody).foregroundStyle(Theme.textSecondary)
            VStack(spacing: 8) {
                primary("Flip object · next pass") { model.nextPass(flipped: true) }
                secondary("Next pass without flipping") { model.nextPass(flipped: false) }
                secondary("Done · build model") { model.finish(store: store) }
            }
        }
        .padding(22)
        .background(Theme.background.opacity(0.96), in: Rectangle())
        .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 0.5))
        .padding(20)
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.fsButton).tracking(Theme.tracking)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Color.white, in: Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.fsButton).tracking(Theme.tracking)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .overlay(Rectangle().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Capture stopped").font(.fsTitle)
            Text(message).font(.fsBody).foregroundStyle(Theme.textSecondary)
            Spacer()
            primary("Close") {
                model.discard(store: store)
                dismiss()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Build

    private func startBuild() {
        guard let pid = model.projectID, let oid = model.objectID else { return }
        let count = ObjectReconstructor.imageCount(in: StoragePaths.objectFile(pid, objectID: oid, .images))
        store.updateObject(pid, oid) { $0.imageCount = count }
        builder.run(store: store, projectID: pid, objectID: oid)
    }

    private func openObject() {
        guard let pid = model.projectID, let oid = model.objectID else { dismiss(); return }
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            router.popToRoot()
            router.open(.project(pid))
            router.open(.object(projectID: pid, objectID: oid))
        }
    }

    private func closeKeepingImages() {
        builder.cancel()
        dismiss()
    }
}

/// Progress for an on-device model build (shared by the capture flow and the object page).
struct ObjectBuildProgressView: View {
    @ObservedObject var builder: ObjectReconstructor
    var onOpen: (() -> Void)? = nil
    var onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            switch builder.phase {
            case .failed(let message):
                Text("Model build failed").font(.fsTitle)
                Text(message).font(.fsBody).foregroundStyle(Theme.textSecondary)
                Text("The capture images are kept. Try again from the object page, or build on a Mac with Reality Composer Pro.")
                    .font(.fsCaption).foregroundStyle(Theme.textTertiary)
            case .finished:
                Text("Model ready").font(.fsTitle)
                Text("Textured USDZ and Unreal-ready GLB saved.").font(.fsBody).foregroundStyle(Theme.textSecondary)
            default:
                Text(builder.phase == .converting ? "Preparing GLB" : "Building model").font(.fsTitle)
                Text(String(format: "%3.0f %%", builder.progress * 100))
                    .font(.fsBigValue)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                    .overlay(alignment: .leading) {
                        GeometryReader { g in
                            Rectangle().fill(Color.white).frame(width: g.size.width * builder.progress, height: 1)
                        }
                    }
                Text("Keep FrameScout open with the screen on. A few minutes is normal; if you leave, the images are kept and you can build later from the object page.")
                    .font(.fsCaption).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            if builder.phase == .finished {
                if let onOpen {
                Button(action: onOpen) {
                    Text("Open object").font(.fsButton).tracking(Theme.tracking)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.white, in: Rectangle())
                }
                .buttonStyle(.plain)
                }
            } else {
                Button(action: onLater) {
                    Text(builder.isBusy ? "Stop · build later" : "Close").font(.fsButton).tracking(Theme.tracking)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .overlay(Rectangle().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
