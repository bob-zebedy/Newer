import Foundation

extension DirectoryAuthorizationStore {
    nonisolated func authorizedDirectories(retryPending: Bool = false) throws -> [AuthorizedDirectory] {
        let records = try storage.load().records
        return try records.map { record in
            var replacement = record
            let status: DirectoryAuthorizationStatus
            do {
                let resolution = try DirectoryAuthorizationBookmark.resolvePersistent(record.applicationBookmark)
                let access = try SecurityScopedDirectoryAccess(directoryURL: resolution.url)
                status = try withExtendedLifetime(access) {
                    try validateDirectory(access.directoryURL)
                    replacement.path = access.directoryURL.resolvingSymlinksInPath().standardizedFileURL.path
                    if resolution.isStale {
                        replacement.applicationBookmark = try DirectoryAuthorizationBookmark.makePersistent(for: access.directoryURL)
                    }
                    if record.shouldRenewHandoff(retryPending: retryPending) {
                        replacement.handoffBookmark = try DirectoryAuthorizationBookmark.makeHandoff(for: access.directoryURL)
                        replacement.revision = UUID()
                        replacement.handoffAttempts = retryPending ? 1 : record.handoffAttempts + 1
                        replacement.handoffCreatedAt = Date()
                        replacement.finderStatus = .waitingForExtension
                    }
                    return replacement.finderStatus
                }
            } catch {
                return AuthorizedDirectory(
                    id: record.id, path: record.path,
                    status: isVolumeUnavailable(record) ? .unavailable : .needsAuthorization
                )
            }
            // 存储错误必须上抛, 不能被当作某个目录的书签错误
            try replace(record, with: replacement)
            return AuthorizedDirectory(id: record.id, path: replacement.path, status: status)
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
