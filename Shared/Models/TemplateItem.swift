import Foundation

nonisolated struct TemplateItem: Codable, Equatable, Sendable {
    static let maximumDirectoryDepth = 3

    var relativePath: String
    var displayName: String
    var isEnabled: Bool

    init(
        relativePath: String,
        displayName: String,
        isEnabled: Bool = true
    ) {
        self.relativePath = relativePath
        self.displayName = displayName
        self.isEnabled = isEnabled
    }

    var pathComponents: [String]? {
        Self.pathComponents(for: relativePath)
    }

    var menuDisplayName: String {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty
            ? Self.defaultDisplayName(for: relativePath)
            : trimmedName
    }

    static func pathComponents(for relativePath: String) -> [String]? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return nil }
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        guard components.count <= maximumDirectoryDepth + 1 else { return nil }
        return components
    }

    static func defaultDisplayName(for relativePath: String) -> String {
        URL(fileURLWithPath: relativePath).lastPathComponent
    }
}

nonisolated struct NewerConfiguration: Codable, Equatable, Sendable {
    static let currentVersion = 3

    var version = Self.currentVersion
    var templates: [TemplateItem] = []
}
