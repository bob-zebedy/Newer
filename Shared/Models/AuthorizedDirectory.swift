import Foundation

nonisolated struct AuthorizedDirectory: Identifiable, Equatable, Sendable {
    let id: UUID
    let path: String
    let status: DirectoryAuthorizationStatus

    init(
        id: UUID = UUID(),
        path: String,
        status: DirectoryAuthorizationStatus = .ready
    ) {
        self.id = id
        self.path = path
        self.status = status
    }

    var isAvailable: Bool {
        status == .ready
    }

    var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }
}

nonisolated enum DirectoryAuthorizationStatus: String, Codable, Sendable {
    case waitingForExtension
    case ready
    case unavailable
    case needsAuthorization
    case retryRequired
}
