import PhotosUI
import SwiftUI
import UIKit

struct PhotoGalleryView: View {
    let ref: LocationRef
    @EnvironmentObject private var store: ProjectStore
    @State private var showCamera = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var viewing: ReferencePhoto?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 6)]

    var body: some View {
        let photos = store.location(ref)?.photos ?? []
        ScrollView {
            if photos.isEmpty {
                EmptyStateView(systemImage: "photo.on.rectangle", title: "No reference photos",
                               message: "Take photos here, snap them during a scan, or grab frames in the lens viewfinder.")
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(photos) { photo in
                    StoredImage(url: StoragePaths.photoURL(ref, photo), maxPixel: 400)
                        .frame(minHeight: 110, maxHeight: 110)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .overlay(alignment: .bottomLeading) {
                            if photo.source == .viewfinder || photo.source == .scan {
                                Image(systemName: photo.source == .scan ? "cube.transparent" : "camera.viewfinder")
                                    .font(.caption2)
                                    .padding(4)
                                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                                    .padding(4)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { viewing = photo }
                }
            }
            .padding(6)
        }
        .fsScreen()
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 30, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                }
                Button { showCamera = true } label: { Image(systemName: "camera") }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            SystemCameraPicker { image in
                if let jpeg = image.downsampled(maxPixel: 4000)?.jpegData(compressionQuality: 0.85) {
                    store.addPhoto(jpeg, to: ref, source: .camera)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $viewing) { photo in
            PhotoDetailView(ref: ref, photo: photo)
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let jpeg = UIImage(data: data)?.downsampled(maxPixel: 4000)?.jpegData(compressionQuality: 0.85) {
                        store.addPhoto(jpeg, to: ref, source: .library)
                    }
                }
                pickerItems = []
            }
        }
    }
}

struct PhotoDetailView: View {
    let ref: LocationRef
    let photo: ReferencePhoto
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var share: SharedFile?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                StoredImage(url: StoragePaths.photoURL(ref, photo), maxPixel: 2400, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Caption", text: $caption)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveCaption)
                    HStack {
                        Text(photo.createdAt.formatted(date: .abbreviated, time: .shortened))
                        if let lens = photo.lensDescription { Text("· \(lens)") }
                        if photo.pose != nil { Text("· position recorded in scan") }
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
            .fsScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { saveCaption(); dismiss() } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { share = SharedFile(url: StoragePaths.photoURL(ref, photo)) } label: { Image(systemName: "square.and.arrow.up") }
                    Button(role: .destructive) {
                        store.deletePhoto(photo, from: ref)
                        dismiss()
                    } label: { Image(systemName: "trash") }
                }
            }
            .sheet(item: $share) { file in ShareSheet(items: [file.url]) }
            .onAppear { caption = photo.caption }
        }
    }

    private func saveCaption() {
        store.updateLocation(ref) { loc in
            if let i = loc.photos.firstIndex(where: { $0.id == photo.id }) { loc.photos[i].caption = caption }
        }
    }
}

/// The system camera (UIImagePickerController) for quick stills.
struct SystemCameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: SystemCameraPicker
        init(_ parent: SystemCameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
