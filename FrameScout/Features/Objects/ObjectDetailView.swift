import QuickLook
import SceneKit
import SwiftUI

/// One scanned object: 3D preview, AR Quick Look, figures, and the exports (Unreal pack,
/// GLB, USDZ, raw capture images for a high-detail rebuild on a Mac).
struct ObjectDetailView: View {
    let projectID: UUID
    let objectID: UUID
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var builder = ObjectReconstructor()
    @State private var share: SharedFile?
    @State private var quickLook: URL?
    @State private var working: String?
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @State private var renaming = false
    @State private var renameText = ""
    @State private var includeImages = false

    private var object: CapturedObject? { store.object(projectID, objectID) }
    private var usdz: URL { StoragePaths.objectFile(projectID, objectID: objectID, .usdz) }
    private var glb: URL { StoragePaths.objectFile(projectID, objectID: objectID, .glb) }
    private var images: URL { StoragePaths.objectFile(projectID, objectID: objectID, .images) }
    private var hasModel: Bool { FileManager.default.fileExists(atPath: usdz.path) }

    var body: some View {
        Group {
            if let object {
                content(object)
            } else {
                EmptyStateView(systemImage: "cube", title: "Object not found", message: "").fsScreen()
            }
        }
        .navigationTitle(object?.name ?? "Object")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $share) { ShareSheet(items: [$0.url]) }
        .quickLookPreview($quickLook)
        .alert("Rename object", isPresented: $renaming) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { store.updateObject(projectID, objectID) { $0.name = trimmed } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Export failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .confirmationDialog("Delete this object and its capture images?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.deleteObject(projectID, objectID)
                dismiss()
            }
        }
    }

    private func content(_ object: CapturedObject) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                preview(object)

                if builder.phase != .idle {
                    ObjectBuildProgressView(builder: builder, onLater: { builder.cancel() })
                        .frame(minHeight: 260)
                        .card(padding: 0)
                }

                figures(object)

                if hasModel {
                    SectionHeader(title: "Export")
                    VStack(spacing: 0) {
                        Toggle(isOn: $includeImages) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Include capture images").font(.fsBody)
                                Text("For a full-detail rebuild on a Mac (Reality Composer Pro / PhotogrammetrySession). Large.")
                                    .font(.fsCaption).foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .padding(.bottom, 8)
                        MenuRow(title: "Unreal pack", subtitle: "GLB + OBJ (cm, Z up) + USDZ + import notes, zipped",
                                trailing: working == "pack" ? "…" : nil) { exportPack(object) }
                        MenuRow(title: "GLB", subtitle: "Textured glTF binary · Unreal 5, Blender, Maya",
                                trailing: working == "glb" ? "…" : nil) { shareGLB(object) }
                        MenuRow(title: "USDZ", subtitle: "Apple's original · Reality Composer, Unreal USD importer") {
                            shareCopy(of: usdz, named: "\(StoragePaths.safeName(object.name)).usdz")
                        }
                        MenuRow(title: "View in AR", subtitle: "Place it at real size with Quick Look") { quickLook = usdz }
                    }
                } else if !builder.isBusy {
                    SectionHeader(title: "Model")
                    Text(object.status == .failed
                         ? "The last build failed: \(object.failureReason ?? "unknown error")."
                         : "The capture images are saved but the model hasn't been built yet.")
                        .font(.fsBody).foregroundStyle(Theme.textSecondary)
                    MenuRow(title: "Build model", subtitle: "On this phone · a few minutes") {
                        builder.run(store: store, projectID: projectID, objectID: objectID)
                    }
                    MenuRow(title: "Share capture images", subtitle: "Build on a Mac at full detail instead") {
                        exportImagesOnly(object)
                    }
                }

                SectionHeader(title: "Notes")
                TextField("Material, condition, who owns it…", text: Binding(
                    get: { store.object(projectID, objectID)?.notes ?? "" },
                    set: { v in store.updateObject(projectID, objectID) { $0.notes = v } }), axis: .vertical)
                    .font(.fsBody)
                    .lineLimit(2...6)
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
            }
            .padding()
        }
        .fsScreen()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { renameText = object.name; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                    if hasModel {
                        Button { builder.run(store: store, projectID: projectID, objectID: objectID) } label: {
                            Label("Rebuild model", systemImage: "arrow.clockwise")
                        }
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .regular))
                }
            }
        }
    }

    @ViewBuilder
    private func preview(_ object: CapturedObject) -> some View {
        if hasModel {
            ModelPreview(url: usdz)
                .frame(height: 340)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
            Text("Drag to orbit · pinch to zoom")
                .font(.fsMicro).foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity)
        } else {
            Rectangle()
                .fill(Theme.surface)
                .frame(height: 220)
                .overlay(Text("No model yet").font(.fsCaption).foregroundStyle(Theme.textTertiary))
        }
    }

    private func figures(_ object: CapturedObject) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(object.name).font(.fsTitle)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                StatView(label: "Size w × h × d", value: object.dimensionsSummary ?? "—", highlight: true)
                StatView(label: "Triangles", value: object.triangleCount > 0 ? object.triangleCount.formatted() : "—")
                StatView(label: "Capture images", value: "\(object.imageCount)")
                StatView(label: "Passes", value: "\(object.scanPasses)")
            }
            Text("Captured \(object.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(object.deviceModel)")
                .font(.fsMono).foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: Exports

    private func exportPack(_ object: CapturedObject) {
        let pid = projectID, images = includeImages
        run("pack") {
            try ObjectExport.buildUnrealPack(object: object, projectID: pid, includeImages: images)
        }
    }

    private func shareGLB(_ object: CapturedObject) {
        let glb = self.glb, usdz = self.usdz
        let name = object.name
        run("glb") {
            if !FileManager.default.fileExists(atPath: glb.path) {
                try ObjectModelConverter.writeGLB(usdz: usdz, to: glb, name: name)
            }
            return try ObjectExport.copyForSharing(glb, named: "\(StoragePaths.safeName(name)).glb")
        }
    }

    private func exportImagesOnly(_ object: CapturedObject) {
        let pid = projectID
        run("images") { try ObjectExport.buildImagesArchive(object: object, projectID: pid) }
    }

    private func shareCopy(of url: URL, named name: String) {
        run("copy") { try ObjectExport.copyForSharing(url, named: name) }
    }

    /// Runs file work off the main thread, then offers the result in the share sheet.
    private func run(_ id: String, _ work: @escaping @Sendable () throws -> URL) {
        guard working == nil else { return }
        working = id
        Task {
            do {
                let url = try await Task.detached(priority: .userInitiated) { try work() }.value
                share = SharedFile(url: url)
            } catch {
                errorMessage = error.localizedDescription
            }
            working = nil
        }
    }
}

/// SceneKit turntable of the USDZ.
struct ModelPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(Theme.background)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.scene = try? SCNScene(url: url, options: [.checkConsistency: false])
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}
}

/// Thumbnail for lists (falls back to a hairline frame).
struct ObjectThumbnail: View {
    let projectID: UUID
    let object: CapturedObject

    var body: some View {
        let url = StoragePaths.objectFile(projectID, objectID: object.id, .thumbnail)
        ZStack {
            Theme.surface
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Text(object.status == .ready ? "" : "not built")
                    .font(.fsMicro).foregroundStyle(Theme.textTertiary)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
    }
}
