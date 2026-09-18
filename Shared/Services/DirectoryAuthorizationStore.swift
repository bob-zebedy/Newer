import Foundation

nonisolated enum DirectoryAuthorizationError: LocalizedError {
    case sharedStorageUnavailable
    case invalidConfiguration
    case missingAuthorization
    case invalidAuthorization
    case accessDenied(String)
    case targetOutsideAuthorizedDirectory(String)

    var errorDescription: String? {
        switch self {
        case .sharedStorageUnavailable:
            String(localized: "error.authorization.shared-storage-unavailable")
        case .invalidConfiguration:
            String(localized: "error.authorization.invalid-configuration")
        case .missingAuthorization:
            String(localized: "error.authorization.missing")
        case .invalidAuthorization:
            String(localized: "error.authorization.invalid")
        case let .accessDenied(path):
            String.localizedStringWithFormat(String(localized: "error.authorization.access-denied"), path)
        case let .targetOutsideAuthorizedDirectory(path):
            String.localizedStringWithFormat(String(localized: "error.authorization.outside-scope"), path)
        }
    }
}

nonisolated struct DirectoryAuthorizationStore: Sendable {
    static let shared = DirectoryAuthorizationStore()
    static let changeNotification = Notification.Name("app.zabrian.newer.directory-authorizations.changed")

    let storage: DirectoryAuthorizationStorage
    let deviceIdentifier: @Sendable (URL) -> UInt64?

    init(
        fileURL: URL = UserPaths.directoryAuthorizationsFile,
        lockFileURL: URL = UserPaths.directoryAuthorizationsLockFile,
        deviceIdentifier: @escaping @Sendable (URL) -> UInt64? = SecurityScopedDirectoryAccess.deviceIdentifier(for:)
    ) {
        storage = DirectoryAuthorizationStorage(fileURL: fileURL, lockFileURL: lockFileURL)
        self.deviceIdentifier = deviceIdentifier
    }

    func saveAuthorization(for directoryURL: URL) throws {
        try validateDirectory(directoryURL)
        let applicationBookmark = try DirectoryAuthorizationBookmark.makePersistent(for: directoryURL)
        let handoffBookmark = try DirectoryAuthorizationBookmark.makeHandoff(for: directoryURL)
        let normalizedPath = directoryURL.resolvingSymlinksInPath().standardizedFileURL.path
        let volumePath = try directoryURL.resourceValues(forKeys: [.volumeURLKey]).volume?.path
        try storage.update { configuration in
            let existing = configuration.records.firstIndex { $0.path == normalizedPath }
            let record = DirectoryAuthorizationRecord(
                id: existing.map { configuration.records[$0].id } ?? UUID(),
                path: normalizedPath,
                volumePath: volumePath,
                applicationBookmark: applicationBookmark,
                finderBookmark: nil,
                handoffBookmark: handoffBookmark
            )
            if let existing {
                configuration.records[existing] = record
            } else {
                configuration.records.append(record)
            }
        }
        postChangeNotification()
    }

    func removeAuthorization(id: UUID) throws {
        try storage.update { configuration in
            configuration.records.removeAll { $0.id == id }
        }
        postChangeNotification()
    }

    func replace(_ record: DirectoryAuthorizationRecord, with replacement: DirectoryAuthorizationRecord) throws {
        if try storage.replace(record, with: replacement) {
            postChangeNotification()
        }
    }

    func isVolumeUnavailable(_ record: DirectoryAuthorizationRecord) -> Bool {
        guard let volumePath = record.volumePath, volumePath.hasPrefix("/Volumes/"),
              let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil) else { return false }
        return !volumes.contains { $0.standardizedFileURL.path == volumePath }
    }

    func validateDirectory(_ url: URL) throws {
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw DirectoryAuthorizationError.accessDenied(url.path)
        }
    }

    func postChangeNotification() {
        DistributedNotificationCenter.default().postNotificationName(
            Self.changeNotification, object: nil, userInfo: nil, options: [.deliverImmediately]
        )
    }
}
