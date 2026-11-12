import PhotosUI
import SwiftUI
import UIKit

/// "From a listing": for a place you can't recce. Add the photos from a studio or location website
/// and paste its description; the sizes in the text (and any text the phone can read in the photos)
/// become a drawn room you can check and adjust before building it. The photos and the listing text
/// are kept with the location. Every size is someone else's figure, so it's saved as entered by hand.
struct BuildFromListingView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var name = "Studio"
    @State private var text: String
    @State private var reading: ListingReader.Reading
    @State private var room: DrawnRoom
    @State private var projectID: UUID?
    /// Opened from a project: the new room goes there unless the user picks another.
    var intoProject: UUID? = nil
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photos: [ListingPhoto] = []
    @State private var readingPhotos = 0
    @FocusState private var editingText: Bool

    private static let myRooms = "My rooms"

    struct ListingPhoto: Identifiable {
        let id = UUID()
        let image: UIImage
        let jpeg: Data
    }

    init(sampleText: String = "", intoProject: UUID? = nil) {
        self.intoProject = intoProject
        let r = ListingReader.read(sampleText)
        _text = State(initialValue: sampleText)
        _reading = State(initialValue: r)
        _room = State(initialValue: r.room())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Can't get to the place? Add the photos and paste the sizes from the studio's website. You can check and change everything before the room is built.")
                        .font(HomeStyle.body).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    field(TextField("Name, e.g. Studio 2", text: $name).textInputAutocapitalization(.words))

                    photosSection
                    textSection
                    if !reading.findings.isEmpty || !text.isEmpty { foundSection }

                    Text("The room").font(HomeStyle.section).foregroundStyle(Theme.textPrimary).padding(.top, 8)
                    shapePicker
                    FloorPlanCanvas(plan: room.plan, style: .thumbnail)
                        .frame(height: 190)
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
                    Text(reading.sizeNote).font(HomeStyle.footnote).foregroundStyle(Theme.textSecondary)

                    StepperRow(title: "Length", value: UnitsFormatter.distance(room.normalised.length),
                               minus: { room.length = step(room.length, -0.1, DrawnRoom.sizeRange) },
                               plus: { room.length = step(room.length, 0.1, DrawnRoom.sizeRange) })
                    StepperRow(title: "Width", value: UnitsFormatter.distance(room.normalised.width),
                               minus: { room.width = step(room.width, -0.1, DrawnRoom.sizeRange) },
                               plus: { room.width = step(room.width, 0.1, DrawnRoom.sizeRange) })
                    StepperRow(title: "Ceiling height", note: reading.ceiling == nil ? "Not in the listing" : "From the listing",
                               value: UnitsFormatter.distance(room.normalised.ceiling),
                               minus: { room.ceiling = step(room.ceiling, -0.1, DrawnRoom.ceilingRange) },
                               plus: { room.ceiling = step(room.ceiling, 0.1, DrawnRoom.ceilingRange) })
                    StepperRow(title: "Windows", note: reading.windows == nil ? "Not in the listing" : "From the listing", value: "\(room.windows)",
                               minus: { room.windows = max(0, room.windows - 1) },
                               plus: { room.windows = min(4, room.windows + 1) })
                    Toggle(isOn: $room.door) { Text("Door on the left wall").font(HomeStyle.body) }
                        .tint(Theme.accent)
                        .padding(.horizontal, 16).frame(minHeight: 56)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.hairline, lineWidth: 1))

                    HStack {
                        Text("Add it to").font(HomeStyle.body)
                        Spacer()
                        Picker("Project", selection: $projectID) {
                            Text("\(Self.myRooms) (new)").tag(UUID?.none)
                            ForEach(store.recentProjects) { p in Text(p.name).tag(UUID?.some(p.id)) }
                        }
                        .tint(Theme.accent)
                    }
                    .padding(.horizontal, 16).frame(minHeight: 56)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.hairline, lineWidth: 1))

                    Text("Sizes from a listing are saved as entered by hand, not as measurements. Check them on the day if you can.")
                        .font(HomeStyle.footnote).foregroundStyle(Theme.textSecondary)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .fsScreen()
            .safeAreaInset(edge: .bottom) {
                Button(action: build) {
                    Label("Build the 3D room", systemImage: "cube")
                        .font(HomeStyle.button)
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Theme.surface)
            }
            .navigationTitle("From a listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .keyboard) {
                    HStack { Spacer(); Button("Done") { editingText = false } }
                }
            }
        }
        .onAppear {
            if projectID == nil { projectID = intoProject ?? store.recentProjects.first { $0.name == Self.myRooms }?.id }
        }
        .onChange(of: text) { _, newText in reread(newText) }
        .onChange(of: pickerItems) { _, items in addPhotos(items) }
    }

    // MARK: Sections

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Photos").font(HomeStyle.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .images) {
                    Label(photos.isEmpty ? "Add photos" : "Add more", systemImage: "photo.badge.plus")
                        .font(HomeStyle.button).foregroundStyle(Theme.accent)
                        .frame(minHeight: HomeStyle.minTap)
                }
            }
            if photos.isEmpty {
                Text("Screenshots of the studio's pages work too. Any sizes printed in a photo are read on this phone and added to the text below.")
                    .font(HomeStyle.footnote).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos) { photo in
                            Image(uiImage: photo.image)
                                .resizable().scaledToFill()
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button { photos.removeAll { $0.id == photo.id } } label: {
                                        Image(systemName: "xmark.circle.fill").font(.title3)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                            .frame(width: 44, height: 44)
                                    }
                                    .accessibilityLabel("Remove photo")
                                }
                        }
                    }
                }
            }
            if readingPhotos > 0 {
                Label("Reading text in \(readingPhotos == 1 ? "the photo" : "\(readingPhotos) photos")…", systemImage: "text.viewfinder")
                    .font(HomeStyle.footnote).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sizes and description").font(HomeStyle.headline).foregroundStyle(Theme.textPrimary)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Paste from the website, e.g.\nStudio 2: 15m x 10m x 6m to grid. Two windows. Loading door 3m x 4m.")
                        .font(HomeStyle.body).foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 5).padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(HomeStyle.body)
                    .focused($editingText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 130)
            }
            .padding(8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
            if UIPasteboard.general.hasStrings {
                Button { if let s = UIPasteboard.general.string { text = text.isEmpty ? s : text + "\n" + s } } label: {
                    Label("Paste", systemImage: "doc.on.clipboard").font(HomeStyle.button).foregroundStyle(Theme.accent)
                        .frame(minHeight: HomeStyle.minTap)
                }
            }
        }
    }

    private var foundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Found in the listing").font(HomeStyle.headline).foregroundStyle(Theme.textPrimary)
            if reading.findings.isEmpty {
                Text("No sizes yet. Try a line like “12 x 8 m, 4 m ceiling”.")
                    .font(HomeStyle.footnote).foregroundStyle(Theme.textTertiary)
            }
            ForEach(Array(reading.findings.enumerated()), id: \.offset) { _, f in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol(f.kind))
                        .foregroundStyle(f.kind == .skipped ? Theme.textTertiary : Theme.accent)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.text).font(HomeStyle.body)
                            .foregroundStyle(f.kind == .skipped ? Theme.textTertiary : Theme.textPrimary)
                        Text("“\(f.quote)”").font(HomeStyle.footnote).foregroundStyle(Theme.textTertiary).lineLimit(2)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if !reading.alternatives.isEmpty {
                Text("Other sizes in the listing").font(HomeStyle.footnote).foregroundStyle(Theme.textSecondary).padding(.top, 4)
                ForEach(Array(reading.alternatives.enumerated()), id: \.offset) { _, alt in
                    Button {
                        room.length = alt.length
                        room.width = alt.width
                        if let c = alt.ceiling { room.ceiling = c }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use \(ListingReader.fmt(alt.length)) × \(ListingReader.fmt(alt.width)) m").font(HomeStyle.button)
                                Text(alt.quote).font(HomeStyle.footnote).foregroundStyle(Theme.textTertiary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "arrow.uturn.down")
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 14).frame(minHeight: 52)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }

    private var shapePicker: some View {
        HStack(spacing: 12) {
            ForEach(DrawnRoom.Shape.allCases) { shape in
                let on = room.shape == shape
                Button { room.shape = shape } label: {
                    HStack(spacing: 8) {
                        Image(systemName: shape == .box ? "rectangle" : "rectangle.split.2x2")
                        Text(shape.label).font(HomeStyle.button)
                    }
                    .foregroundStyle(on ? Theme.accent : Theme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(on ? Theme.surfaceRaised : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(on ? Theme.accent : Theme.hairline, lineWidth: on ? 2 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func field<V: View>(_ content: V) -> some View {
        content
            .font(HomeStyle.body)
            .padding(.horizontal, 14).frame(minHeight: 52)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }

    private func symbol(_ kind: ListingReader.FindingKind) -> String {
        switch kind {
        case .size: return "ruler"
        case .ceiling: return "arrow.up.and.down"
        case .area: return "square.dashed"
        case .windows: return "window.vertical.closed"
        case .door: return "door.left.hand.closed"
        case .skipped: return "minus.circle"
        }
    }

    // MARK: Actions

    /// New text re-reads the sizes. What the listing says replaces the room's figures; what it
    /// doesn't say keeps whatever is set now.
    private func reread(_ newText: String) {
        reading = ListingReader.read(newText)
        let shape = room.shape
        room = reading.room(base: room)
        room.shape = shape
    }

    private func addPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        pickerItems = []
        readingPhotos += items.count
        Task {
            for item in items {
                defer { readingPhotos -= 1 }
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)?.downsampled(maxPixel: 4000),
                      let jpeg = image.jpegData(compressionQuality: 0.85) else { continue }
                photos.append(ListingPhoto(image: image, jpeg: jpeg))
                let found = await ListingPhotoText.read(image).trimmingCharacters(in: .whitespacesAndNewlines)
                // Only text that holds a figure is worth adding; captions and logos are left out.
                if found.rangeOfCharacter(from: .decimalDigits) != nil {
                    let header = "From photo \(photos.count):"
                    text = text.isEmpty ? "\(header)\n\(found)" : "\(text)\n\n\(header)\n\(found)"
                }
            }
        }
    }

    private func step(_ value: Double, _ by: Double, _ range: ClosedRange<Double>) -> Double {
        let next = ((value + by) * 10).rounded() / 10
        return min(range.upperBound, max(range.lowerBound, next))
    }

    private func build() {
        let target = projectID.flatMap { store.project($0)?.id } ?? store.createProject(name: Self.myRooms).id
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ref = store.addDrawnRoom(room, name: title.isEmpty ? "Studio" : title, to: target) else { return }
        let listing = text.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateLocation(ref) { loc in
            if !listing.isEmpty {
                loc.notes = loc.notes.isEmpty ? "From the listing:\n\(listing)" : "\(loc.notes)\n\nFrom the listing:\n\(listing)"
            }
            if listing.lowercased().contains("studio") { loc.tags.insert(.studio) }
            loc.tags.insert(.interior)
            if let i = loc.scans.indices.last {
                loc.scans[i].notes = "Built from a listing. Sizes were copied from the listing, not measured."
            }
        }
        for photo in photos {
            _ = store.addPhoto(photo.jpeg, to: ref, source: .library, caption: "From the listing")
        }
        dismiss()
        router.show([.project(target), .location(ref), .lighting(ref)])
    }
}

#if DEBUG
extension BuildFromListingView {
    /// Shown by the `listing` demo screen for Simulator screenshots.
    static let sampleListing = """
    Studio 2
    Shooting space: 15m x 10m x 6m to grid.
    Two large windows on the north wall, full blackout.
    Loading door 3m x 4m.
    Studio 1: 9m x 7m, ceiling 3.5m
    """
}
#endif
