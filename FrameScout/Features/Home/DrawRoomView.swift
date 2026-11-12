import SwiftUI

/// "Draw a plan": pick a starting shape, set the sizes with big plus and minus buttons, and get a
/// floor plan that the 3D view raises into a room. Nothing here is measured, so it is saved as
/// entered by hand.
struct DrawRoomView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @State private var name = "New room"
    @State private var room = DrawnRoom()
    @State private var projectID: UUID?

    private static let myRooms = "My rooms"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Room name", text: $name)
                        .font(HomeStyle.body)
                        .textInputAutocapitalization(.words)
                        .padding(.horizontal, 14).frame(minHeight: 52)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.hairline, lineWidth: 1))

                    Text("Start from a shape").font(HomeStyle.footnote).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 12) {
                        ForEach(DrawnRoom.Shape.allCases) { shape in
                            let on = room.shape == shape
                            Button { room.shape = shape } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: shape == .box ? "rectangle" : "rectangle.split.2x2")
                                        .font(.title2)
                                    Text(shape.label).font(HomeStyle.button)
                                }
                                .foregroundStyle(on ? Theme.accent : Theme.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 76)
                                .background(on ? Theme.surfaceRaised : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(on ? Theme.accent : Theme.hairline, lineWidth: on ? 2 : 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }

                    FloorPlanCanvas(plan: room.plan, style: .thumbnail)
                        .frame(height: 190)
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.hairline, lineWidth: 1))

                    StepperRow(title: "Length", value: UnitsFormatter.distance(room.normalised.length),
                               minus: { room.length = step(room.length, -0.1, DrawnRoom.sizeRange) },
                               plus: { room.length = step(room.length, 0.1, DrawnRoom.sizeRange) })
                    StepperRow(title: "Width", value: UnitsFormatter.distance(room.normalised.width),
                               minus: { room.width = step(room.width, -0.1, DrawnRoom.sizeRange) },
                               plus: { room.width = step(room.width, 0.1, DrawnRoom.sizeRange) })
                    StepperRow(title: "Ceiling height", note: "Used to build the 3D room", value: UnitsFormatter.distance(room.normalised.ceiling),
                               minus: { room.ceiling = step(room.ceiling, -0.1, DrawnRoom.ceilingRange) },
                               plus: { room.ceiling = step(room.ceiling, 0.1, DrawnRoom.ceilingRange) })
                    StepperRow(title: "Windows", note: "Along the top wall", value: "\(room.windows)",
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

                    Text("Sizes you set here are saved as entered by hand, not as measurements.")
                        .font(HomeStyle.footnote).foregroundStyle(Theme.textSecondary)
                }
                .padding(16)
            }
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
            .navigationTitle("Draw a plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .onAppear {
            if projectID == nil { projectID = store.recentProjects.first { $0.name == Self.myRooms }?.id }
        }
    }

    private func step(_ value: Double, _ by: Double, _ range: ClosedRange<Double>) -> Double {
        let next = ((value + by) * 10).rounded() / 10
        return min(range.upperBound, max(range.lowerBound, next))
    }

    private func build() {
        let target = projectID.flatMap { store.project($0)?.id } ?? store.createProject(name: Self.myRooms).id
        guard let ref = store.addDrawnRoom(room, name: name.trimmingCharacters(in: .whitespacesAndNewlines), to: target) else { return }
        dismiss()
        router.open(.project(target))
        router.open(.location(ref))
        router.open(.lighting(ref))
    }
}

/// A labelled value with large minus and plus buttons, easy to hit one-handed or with gloves.
struct StepperRow: View {
    var title: String
    var note: String? = nil
    var value: String
    var minus: () -> Void
    var plus: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(HomeStyle.body).foregroundStyle(Theme.textPrimary)
                if let note { Text(note).font(HomeStyle.footnote).foregroundStyle(Theme.textSecondary) }
            }
            Spacer(minLength: 4)
            button("minus", "Less \(title.lowercased())", minus)
            Text(value).font(HomeStyle.headline).monospacedDigit().foregroundStyle(Theme.textPrimary)
                .frame(minWidth: 70)
            button("plus", "More \(title.lowercased())", plus)
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func button(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title3.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 52, height: 52)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
