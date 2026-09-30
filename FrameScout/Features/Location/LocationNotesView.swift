import SwiftUI

struct LocationNotesView: View {
    let ref: LocationRef
    @EnvironmentObject private var store: ProjectStore
    @State private var newNote = ""
    @State private var newCategory: NoteCategory = .general

    var body: some View {
        let location = store.binding(for: ref)
        Form {
            Section {
                ForEach(location.wrappedValue.quickNotes) { note in
                    Label(note.text, systemImage: note.category.symbol)
                }
                .onDelete { offsets in
                    store.updateLocation(ref) { $0.quickNotes.remove(atOffsets: offsets) }
                }
                HStack {
                    Menu {
                        ForEach(NoteCategory.allCases) { c in
                            Button { newCategory = c } label: { Label(c.label, systemImage: c.symbol) }
                        }
                    } label: {
                        Image(systemName: newCategory.symbol).frame(width: 28)
                    }
                    TextField("Add a scout note", text: $newNote)
                        .onSubmit(addNote)
                    Button("Add", action: addNote).disabled(newNote.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Scout notes")
            } footer: {
                Text("Short facts the crew needs: power, access, light, sound, restrictions.")
            }

            Section("Quick add") {
                FlowLayout(spacing: 8) {
                    ForEach(LocationNote.templates, id: \.1) { category, text in
                        TagChip(text: text, selected: false) {
                            store.updateLocation(ref) { $0.quickNotes.append(LocationNote(text: text, category: category)) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("General notes") {
                TextField("Access, parking, contacts, restrictions…", text: location.notes, axis: .vertical)
                    .lineLimit(4...12)
            }
            Section("Lighting notes") {
                TextField("Window directions, practicals, best time of day, lighting positions…", text: location.lightingNotes, axis: .vertical)
                    .lineLimit(4...12)
            }
            Section("Production notes") {
                TextField("Space behind camera, dolly access, power, holding area…", text: location.productionNotes, axis: .vertical)
                    .lineLimit(4...12)
            }
        }
        .fsScreen()
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addNote() {
        let text = newNote.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        store.updateLocation(ref) { $0.quickNotes.append(LocationNote(text: text, category: newCategory)) }
        newNote = ""
    }
}
