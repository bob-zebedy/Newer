import CoreGraphics
import Foundation

struct TemplateDragState {
    let id = UUID()
    let entry: TemplateEntry
    let initialEntries: [TemplateEntry]
    let parentRelativePath: String
    let rowFrames: [TemplateEntry.EntryID: CGRect]
    let originIndex: Int
    private(set) var targetIndex: Int
    var translation: CGSize = .zero
    var isSettling = false

    init?(
        entryID: TemplateEntry.EntryID,
        entries: [TemplateEntry],
        parentRelativePath: String,
        rowFrames: [TemplateEntry.EntryID: CGRect]
    ) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return nil }
        entry = entries[index]
        initialEntries = entries
        self.parentRelativePath = parentRelativePath
        self.rowFrames = rowFrames
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
