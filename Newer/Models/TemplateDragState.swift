import Foundation

struct TemplateDragState {
    let id = UUID()
    let entry: TemplateEntry
    let initialEntries: [TemplateEntry]
    let originIndex: Int
    private(set) var targetIndex: Int
    var isSettling = false

    init?(
        entryID: TemplateEntry.EntryID,
        entries: [TemplateEntry]
    ) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return nil }
        entry = entries[index]
        initialEntries = entries
        originIndex = index
        targetIndex = index
    }

    mutating func updateTarget(entryID: TemplateEntry.EntryID) {
        guard let index = initialEntries.firstIndex(where: { $0.id == entryID }) else { return }
        targetIndex = index
    }

    var displayedEntries: [TemplateEntry] {
        var result = initialEntries
        result.remove(at: originIndex)
        result.insert(entry, at: targetIndex)
        return result
    }

    var destinationOffset: Int {
        targetIndex > originIndex ? targetIndex + 1 : targetIndex
    }
}
