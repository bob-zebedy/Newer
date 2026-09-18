import Foundation

nonisolated enum FinderTargetKind: Equatable, Sendable {
    case container
    case item
}

nonisolated enum FinderTargetResolutionError: LocalizedError {
    case targetUnavailable

    var errorDescription: String? {
        String(localized: "finder.error.current-folder-unavailable")
    }
}

nonisolated enum FinderTargetResolver {
    static func resolve(
        targetedURL: URL?,
        selectedItemURLs: [URL]?,
        kind: FinderTargetKind
    ) throws -> URL {
        switch kind {
        case .container:
            guard let targetedURL else {
                throw FinderTargetResolutionError.targetUnavailable
            }
            return targetedURL
        case .item:
            guard let selectedItemURLs, !selectedItemURLs.isEmpty else {
                throw FinderTargetResolutionError.targetUnavailable
            }
            if selectedItemURLs.count == 1, let selectedURL = selectedItemURLs.first {
                return try resolveSelectedItem(selectedURL)
            }

            let parentURLs = Set(selectedItemURLs.map {
                $0.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
            })
            guard parentURLs.count == 1, let parentURL = parentURLs.first else {
                throw FinderTargetResolutionError.targetUnavailable
            }
            return parentURL
        }
    }

    private static func resolveSelectedItem(_ selectedURL: URL) throws -> URL {
        let values: URLResourceValues
        do {
            values = try selectedURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isPackageKey
            ])
        } catch {
            throw FinderTargetResolutionError.targetUnavailable
        }
        guard let isDirectory = values.isDirectory else {
            throw FinderTargetResolutionError.targetUnavailable
        }
        if isDirectory, values.isPackage != true {
            return selectedURL
        }
        return selectedURL.deletingLastPathComponent()
    }
}
