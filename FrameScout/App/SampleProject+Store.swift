import Foundation

extension SampleProject {
    /// Opens the sample if it is already on this phone, otherwise adds a fresh copy (new IDs, so
    /// it syncs like any other project). Returns the project to open.
    @MainActor
    static func addOrFind(in store: ProjectStore) -> Project {
        if let existing = store.projects.first(where: { $0.name == name }) { return existing }
        let scanID = UUID()
        return store.addProject(project(scanID: scanID), plans: [scanID: plan])
    }
}
