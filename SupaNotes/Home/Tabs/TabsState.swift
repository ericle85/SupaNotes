import Foundation
import Observation

@Observable
final class TabsState {
    private static let storeKey = "supanotes.openTabs"

    var openTabIDs: [UUID]
    var activeTabID: UUID?

    init() {
        let raw = UserDefaults.standard.stringArray(forKey: Self.storeKey) ?? []
        let ids = raw.compactMap(UUID.init(uuidString:))
        openTabIDs = ids
        activeTabID = ids.first
    }

    func open(noteID: UUID) {
        if !openTabIDs.contains(noteID) {
            openTabIDs.append(noteID)
        }
        activeTabID = noteID
        persist()
    }

    func close(noteID: UUID) {
        guard let idx = openTabIDs.firstIndex(of: noteID) else { return }
        openTabIDs.remove(at: idx)
        if activeTabID == noteID {
            activeTabID = openTabIDs[safe: idx] ?? openTabIDs.last
        }
        persist()
    }

    func activate(_ noteID: UUID) {
        activeTabID = noteID
        persist()
    }

    private func persist() {
        let strings = openTabIDs.map { $0.uuidString }
        UserDefaults.standard.set(strings, forKey: Self.storeKey)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
