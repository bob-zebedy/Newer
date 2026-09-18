import Foundation

nonisolated enum DirectoryAuthorizationBookmark {
    static func resolvePersistent(_ bookmark: Data) throws -> ResolvedDirectoryAuthorization {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return ResolvedDirectoryAuthorization(url: url, isStale: isStale)
        } catch {
            throw DirectoryAuthorizationError.invalidAuthorization
        }
    }

    static func resolveHandoff(_ bookmark: Data) throws -> URL {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI, .withoutMounting, .withoutImplicitStartAccessing],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard !isStale else {
                throw DirectoryAuthorizationError.invalidAuthorization
            }
            return url
        } catch let error as DirectoryAuthorizationError {
            throw error
        } catch {
            throw DirectoryAuthorizationError.invalidAuthorization
        }
    }

    static func makePersistent(for directoryURL: URL) throws -> Data {
        try directoryURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func makeHandoff(for directoryURL: URL) throws -> Data {
        try directoryURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}

nonisolated struct ResolvedDirectoryAuthorization: Sendable {
    let url: URL
    let isStale: Bool
}
