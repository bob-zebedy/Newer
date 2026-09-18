import SwiftUI

struct TemplateHierarchyRows<Row: View>: View {
    let entries: [TemplateEntry]
    let expandedDirectories: Set<String>
    let depth: Int
    let parentRelativePath: String
    @ViewBuilder let row: (TemplateEntry, Int, String) -> Row

    init(
        entries: [TemplateEntry],
        expandedDirectories: Set<String>,
        depth: Int = 0,
        parentRelativePath: String = "",
        @ViewBuilder row: @escaping (TemplateEntry, Int, String) -> Row
    ) {
        self.entries = entries
        self.expandedDirectories = expandedDirectories
        self.depth = depth
        self.parentRelativePath = parentRelativePath
        self.row = row
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                row(entry, depth, parentRelativePath)
                    .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if case let .directory(path, _, children) = entry,
                   expandedDirectories.contains(path) {
                    TemplateHierarchyRows(
                        entries: children,
                        expandedDirectories: expandedDirectories,
                        depth: depth + 1,
                        parentRelativePath: path,
                        row: row
                    )
                }
            }
        }
    }
}

struct TemplateRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [TemplateEntry.EntryID: CGRect] = [:]

    static func reduce(
        value: inout [TemplateEntry.EntryID: CGRect],
        nextValue: () -> [TemplateEntry.EntryID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
