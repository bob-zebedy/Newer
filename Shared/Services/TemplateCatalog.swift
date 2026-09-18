import Foundation

nonisolated enum TemplateCatalogError: LocalizedError {
    case metadataUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .metadataUnavailable(path):
            String.localizedStringWithFormat(
                String(localized: "error.template.metadata-unavailable"),
                path
            )
        }
    }
}

nonisolated struct TemplateCatalog: Sendable {
    let templateDirectory: URL
    private let configurationStore: ConfigurationStore

    static let shared = TemplateCatalog(
        templateDirectory: UserPaths.templateDirectory,
        configurationStore: .shared
    )

    init(templateDirectory: URL, configurationStore: ConfigurationStore) {
        self.templateDirectory = templateDirectory
        self.configurationStore = configurationStore
    }

    func ensureTemplateDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: templateDirectory,
            withIntermediateDirectories: true
        )
    }

    func snapshot() throws -> [TemplateItem] {
        try ensureTemplateDirectoryExists()

        let relativePaths = try discoverFiles(in: templateDirectory)

        let saved = try configurationStore.load()
        var remainingPaths = Set(relativePaths)
        var templates = saved.templates.filter { template in
            remainingPaths.remove(template.relativePath) != nil
        }
        templates += relativePaths.compactMap { relativePath in
            guard remainingPaths.remove(relativePath) != nil else { return nil }
            return TemplateItem(
                relativePath: relativePath,
                displayName: TemplateItem.defaultDisplayName(for: relativePath)
            )
        }
        return templates
    }

    func save(_ templates: [TemplateItem]) throws {
        try configurationStore.save(NewerConfiguration(templates: templates))
    }

    private func discoverFiles(
        in directory: URL,
        relativeComponents: [String] = []
    ) throws -> [String] {
        let keys: Set<URLResourceKey> = [
            .isAliasFileKey,
            .isDirectoryKey,
            .isPackageKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        var paths: [String] = []
        for url in urls {
            let values = try url.resourceValues(forKeys: keys)
            guard let isSymbolicLink = values.isSymbolicLink,
                  let isAliasFile = values.isAliasFile,
                  let isDirectory = values.isDirectory,
                  let isPackage = values.isPackage,
                  let isRegularFile = values.isRegularFile else {
                throw TemplateCatalogError.metadataUnavailable(url.path)
            }
            guard !isSymbolicLink, !isAliasFile else {
                continue
            }

            let components = relativeComponents + [url.lastPathComponent]
            if isDirectory {
                guard !isPackage,
                      components.count <= TemplateItem.maximumDirectoryDepth else {
                    continue
                }
                paths += try discoverFiles(in: url, relativeComponents: components)
            } else if isRegularFile,
                      components.count <= TemplateItem.maximumDirectoryDepth + 1 {
                paths.append(components.joined(separator: "/"))
            }
        }
        return paths
    }
}
