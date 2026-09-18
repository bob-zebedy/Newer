import Foundation

@MainActor
extension TemplateEntry: Identifiable {
    enum SelectionState: Equatable {
        case disabled
        case mixed
        case enabled
    }

    enum EntryID: Hashable {
        case directory(String)
        case template(String)
    }

    var id: EntryID {
        switch self {
        case let .directory(path, _, _):
            .directory(path)
        case let .template(item):
            .template(item.relativePath)
        }
    }

    var flattenedTemplates: [TemplateItem] {
        switch self {
        case let .directory(_, _, children):
            children.flatMap(\.flattenedTemplates)
        case let .template(item):
            [item]
        }
    }

    var flattenedEntryIDs: [EntryID] {
        switch self {
        case let .directory(_, _, children):
            [id] + children.flatMap(\.flattenedEntryIDs)
        case .template:
            [id]
        }
    }

    var selectionState: SelectionState {
        let templates = flattenedTemplates
        let enabledCount = templates.filter(\.isEnabled).count
        if enabledCount == 0 {
            return .disabled
        }
        if enabledCount == templates.count {
            return .enabled
        }
        return .mixed
    }

    static func entries(
        in hierarchy: [TemplateEntry],
        parentRelativePath: String
    ) -> [TemplateEntry]? {
        guard !parentRelativePath.isEmpty else { return hierarchy }
        for entry in hierarchy {
            guard case let .directory(path, _, children) = entry else { continue }
            if path == parentRelativePath {
                return children
            }
            if let result = entries(in: children, parentRelativePath: parentRelativePath) {
                return result
            }
        }
        return nil
    }

    static func replaceEntries(
        in hierarchy: inout [TemplateEntry],
        parentRelativePath: String,
        with replacement: [TemplateEntry]
    ) -> Bool {
        guard !parentRelativePath.isEmpty else {
            hierarchy = replacement
            return true
        }

        for index in hierarchy.indices {
            guard case let .directory(path, name, children) = hierarchy[index] else { continue }
            if path == parentRelativePath {
                hierarchy[index] = .directory(path: path, name: name, children: replacement)
                return true
            }
            var updatedChildren = children
            if replaceEntries(
                in: &updatedChildren,
                parentRelativePath: parentRelativePath,
                with: replacement
            ) {
                hierarchy[index] = .directory(
                    path: path,
                    name: name,
                    children: updatedChildren
                )
                return true
            }
        }
        return false
    }
}
