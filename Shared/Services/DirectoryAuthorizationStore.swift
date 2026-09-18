import Foundation

nonisolated enum DirectoryAuthorizationError: LocalizedError {
    case sharedStorageUnavailable
    case missingAuthorization
    case invalidAuthorization
    case accessDenied(String)
    case targetOutsideAuthorizedDirectory(String)

    var errorDescription: String? {
        switch self {
        case .sharedStorageUnavailable:
            String(localized: "error.authorization.shared-storage-unavailable")
        case .missingAuthorization:
            String(localized: "error.authorization.missing")
        case .invalidAuthorization:
            String(localized: "error.authorization.invalid")
        case let .accessDenied(path):
            String.localizedStringWithFormat(
                String(localized: "error.authorization.access-denied"),
                path
            )
        case let .targetOutsideAuthorizedDirectory(path):
            String.localizedStringWithFormat(
                String(localized: "error.authorization.outside-scope"),
                path
            )
        }
    }
}

nonisolated struct DirectoryAuthorizationStore: Sendable {
    static let shared = DirectoryAuthorizationStore()

    private let fileURL: URL
    private let deviceIdentifier: @Sendable (URL) -> UInt64?

    init(
        fileURL: URL = UserPaths.directoryAuthorizationsFile,
        deviceIdentifier: @escaping @Sendable (URL) -> UInt64? = SecurityScopedDirectoryAccess.deviceIdentifier(for:)
    ) {
        self.fileURL = fileURL
        self.deviceIdentifier = deviceIdentifier
    }

    func hasAuthorization(containing targetURL: URL) throws -> Bool {
        resolvedRecords().contains { resolution in
            guard resolution.isAvailable, let directoryURL = resolution.resolved?.url else {
                return false
            }
            return SecurityScopedDirectoryAccess.containsOnSameFileSystem(
                targetURL,
                in: directoryURL,
                deviceIdentifier: deviceIdentifier
            )
        }
    }

    func authorizedDirectories() throws -> [AuthorizedDirectory] {
        resolvedRecords().map { resolution in
            AuthorizedDirectory(
                id: resolution.record.id,
                path: resolution.record.path,
                bookmark: resolution.record.bookmark,
                isAvailable: resolution.isAvailable
            )
        }.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    func saveAuthorization(for directoryURL: URL) throws {
        let normalizedURL = directoryURL.resolvingSymlinksInPath().standardizedFileURL
        let bookmark = try makeBookmark(for: directoryURL)

        let resolutions = resolvedRecords()
        var records = resolutions.map(\.record)
        let normalizedPath = normalizedURL.path
        if let index = resolutions.firstIndex(where: { resolution in
            if resolution.record.path == normalizedPath {
                return true
            }
            guard let resolvedURL = resolution.resolved?.url else { return false }
            return resolvedURL.resolvingSymlinksInPath().standardizedFileURL.path == normalizedPath
        }) {
            records[index] = AuthorizedDirectory(
                id: records[index].id,
                path: normalizedPath,
                bookmark: bookmark
            )
        } else {
            records.append(AuthorizedDirectory(path: normalizedPath, bookmark: bookmark))
        }
        try persist(records)
    }

    func removeAuthorization(id: UUID) throws {
        let records = loadRecords().filter { $0.id != id }
        try persist(records)
    }

    func beginAccess(containing targetURL: URL) throws -> SecurityScopedDirectoryAccess {
        let resolutions = resolvedRecords().filter(\.isAvailable)
        guard !resolutions.isEmpty else {
            throw DirectoryAuthorizationError.missingAuthorization
        }

        // Prefer the most specific grant. This is important when both `/` and
        // an external volume are present: the root grant does not necessarily
        // cross a separately mounted volume's security boundary
        let candidates = resolutions.compactMap { resolution -> (AuthorizedDirectory, URL)? in
            guard let resolvedURL = resolution.resolved?.url else { return nil }
            return SecurityScopedDirectoryAccess.containsOnSameFileSystem(
                targetURL,
                in: resolvedURL,
                deviceIdentifier: deviceIdentifier
            )
                ? (resolution.record, resolvedURL)
                : nil
        }.sorted { $0.1.path.count > $1.1.path.count }

        guard !candidates.isEmpty else {
            throw DirectoryAuthorizationError.targetOutsideAuthorizedDirectory(targetURL.path)
        }

        var lastError: Error?
        for (record, _) in candidates {
            do {
                return try beginAccess(to: record)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? DirectoryAuthorizationError.accessDenied(targetURL.path)
    }

    private func resolve(
        _ record: AuthorizedDirectory,
        startsImplicitAccess: Bool = false
    ) throws -> ResolvedDirectoryAuthorization {
        var isStale = false
        var options: URL.BookmarkResolutionOptions = [.withoutUI]
        if !startsImplicitAccess {
            options.insert(.withoutImplicitStartAccessing)
        }
        do {
            let url = try URL(
                resolvingBookmarkData: record.bookmark,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return ResolvedDirectoryAuthorization(url: url, isStale: isStale)
        } catch {
            throw DirectoryAuthorizationError.invalidAuthorization
        }
    }

    private func makeBookmark(for directoryURL: URL) throws -> Data {
        // A regular bookmark preserves the Powerbox grant when passed to the
        // related Finder extension. Resolving it starts the ephemeral scope
        // unless withoutImplicitStartAccessing is requested
        try directoryURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func resolvedRecords() -> [ResolvedDirectoryAuthorizationRecord] {
        loadRecords().map { record in
            guard let resolved = try? resolve(record) else {
                return ResolvedDirectoryAuthorizationRecord(
                    record: record,
                    resolved: nil,
                    isAvailable: false
                )
            }
            let resolvedPath = resolved.url.resolvingSymlinksInPath().standardizedFileURL.path
            return ResolvedDirectoryAuthorizationRecord(
                record: record,
                resolved: resolved,
                isAvailable: !resolved.isStale && resolvedPath == record.url.standardizedFileURL.path
            )
        }
    }

    private func beginAccess(to record: AuthorizedDirectory) throws -> SecurityScopedDirectoryAccess {
        // Keep the exact resolved URL because derived URLs can lose the
        // ephemeral sandbox extension attached during bookmark resolution
        try SecurityScopedDirectoryAccess(
            directoryURL: resolve(record, startsImplicitAccess: true).url
        )
    }

    private func loadRecords() -> [AuthorizedDirectory] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? PropertyListDecoder().decode([AuthorizedDirectory].self, from: data)) ?? []
    }

    private func persist(_ records: [AuthorizedDirectory]) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw DirectoryAuthorizationError.sharedStorageUnavailable
        }
    }
}

private nonisolated struct ResolvedDirectoryAuthorization {
    let url: URL
    let isStale: Bool
}

private nonisolated struct ResolvedDirectoryAuthorizationRecord {
    let record: AuthorizedDirectory
    let resolved: ResolvedDirectoryAuthorization?
    let isAvailable: Bool
}
