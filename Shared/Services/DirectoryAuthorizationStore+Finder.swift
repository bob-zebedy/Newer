import Foundation

extension DirectoryAuthorizationStore {
    nonisolated func prepareFinderAuthorizations(onFailure: (String, Error) -> Void = { _, _ in }) throws -> Int {
        var preparedCount = 0
        for record in try storage.load().records {
            var replacement = record
            do {
                try prepareFinderBookmark(&replacement)
            } catch {
                replacement = record
                replacement.finderStatus = isVolumeUnavailable(record) ? .unavailable : .retryRequired
                // 同一失败只记录一次, 重试由主应用有界地生成新交接
                if record.finderStatus != replacement.finderStatus {
                    onFailure(record.path, error)
                }
            }
            if try storage.replace(record, with: replacement) {
                postChangeNotification()
                if replacement.finderStatus == .ready {
                    preparedCount += 1
                }
            }
        }
        return preparedCount
    }

    private nonisolated func prepareFinderBookmark(_ record: inout DirectoryAuthorizationRecord) throws {
        if let bookmark = record.finderBookmark,
           let refreshed = try? validatedFinderBookmark(bookmark) {
            record.finderBookmark = refreshed
            record.handoffBookmark = nil
            record.finderStatus = .ready
            return
        }
        // 失败的交接等待新版本, 避免每次菜单打开都重复处理同一失效令牌
        if record.finderStatus == .retryRequired {
            return
        }
        if let handoff = record.handoffBookmark {
            let url = try DirectoryAuthorizationBookmark.resolveHandoff(handoff)
            let access = try SecurityScopedDirectoryAccess(directoryURL: url)
            record.finderBookmark = try withExtendedLifetime(access) {
                try validateDirectory(access.directoryURL)
                return try DirectoryAuthorizationBookmark.makePersistent(for: access.directoryURL)
            }
        }
        guard let bookmark = record.finderBookmark else {
            throw DirectoryAuthorizationError.missingAuthorization
        }
        record.finderBookmark = try validatedFinderBookmark(bookmark)
        record.handoffBookmark = nil
        record.finderStatus = .ready
    }

    private nonisolated func validatedFinderBookmark(_ bookmark: Data) throws -> Data {
        let resolution = try DirectoryAuthorizationBookmark.resolvePersistent(bookmark)
        let access = try SecurityScopedDirectoryAccess(directoryURL: resolution.url)
        return try withExtendedLifetime(access) {
            try validateDirectory(access.directoryURL)
            if resolution.isStale {
                return try DirectoryAuthorizationBookmark.makePersistent(for: access.directoryURL)
            }
            return bookmark
        }
    }

    nonisolated func resolveFinderTarget(
        targetedURL: URL?, selectedItemURLs: [URL]?, kind: FinderTargetKind
    ) throws -> AuthorizedFinderTarget {
        let records = try storage.load().records.sorted { $0.path.count > $1.path.count }
        var lastError: Error = DirectoryAuthorizationError.missingAuthorization
        for record in records {
            guard let bookmark = record.finderBookmark else { continue }
            let target: AuthorizedFinderTarget
            do {
                let resolution = try DirectoryAuthorizationBookmark.resolvePersistent(bookmark)
                let access = try SecurityScopedDirectoryAccess(directoryURL: resolution.url)
                target = try withExtendedLifetime(access) {
                    let url = try FinderTargetResolver.resolve(
                        targetedURL: targetedURL, selectedItemURLs: selectedItemURLs, kind: kind
                    )
                    try validateDirectory(access.directoryURL)
                    try validateDirectory(url)
                    guard SecurityScopedDirectoryAccess.containsOnSameFileSystem(
                        url, in: access.directoryURL, deviceIdentifier: deviceIdentifier
                    ) else {
                        throw DirectoryAuthorizationError.targetOutsideAuthorizedDirectory(url.path)
                    }
                    return AuthorizedFinderTarget(url: url, access: access)
                }
            } catch {
                lastError = error
                continue
            }
            // 菜单与动作之间可能移除或重新授权, 不接受旧版本的检查结果
            guard try storage.load().records.contains(where: {
                $0.id == record.id && $0.revision == record.revision && $0.finderBookmark == bookmark
            }) else { continue }
            return target
        }
        throw lastError
    }
}

nonisolated struct AuthorizedFinderTarget {
    let url: URL
    let access: SecurityScopedDirectoryAccess
}
