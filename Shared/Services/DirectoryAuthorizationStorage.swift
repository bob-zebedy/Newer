import Darwin
import Foundation

nonisolated struct DirectoryAuthorizationStorage: Sendable {
    let fileURL: URL
    let lockFileURL: URL

    func load() throws -> DirectoryAuthorizationConfiguration {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return DirectoryAuthorizationConfiguration()
        } catch {
            throw DirectoryAuthorizationError.sharedStorageUnavailable
        }
        guard let configuration = try? PropertyListDecoder().decode(
            DirectoryAuthorizationConfiguration.self, from: data
        ), configuration.schemaVersion == DirectoryAuthorizationConfiguration.currentSchemaVersion else {
            throw DirectoryAuthorizationError.invalidConfiguration
        }
        guard Set(configuration.records.map(\.id)).count == configuration.records.count else {
            throw DirectoryAuthorizationError.invalidConfiguration
        }
        return configuration
    }

    func update<T>(
        _ operation: (inout DirectoryAuthorizationConfiguration) throws -> T
    ) throws -> T {
        try withExclusiveLock {
            var configuration = try load()
            let original = configuration
            let result = try operation(&configuration)
            if configuration != original {
                try persist(configuration)
            }
            return result
        }
    }

    func replace(_ original: DirectoryAuthorizationRecord, with replacement: DirectoryAuthorizationRecord) throws -> Bool {
        guard original != replacement else { return false }
        return try update { configuration in
            guard let index = configuration.records.firstIndex(of: original) else {
                return false
            }
            configuration.records[index] = replacement
            return true
        }
    }

    private func persist(_ configuration: DirectoryAuthorizationConfiguration) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(configuration)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw DirectoryAuthorizationError.sharedStorageUnavailable
        }
    }

    private func withExclusiveLock<T>(_ operation: () throws -> T) throws -> T {
        do {
            try FileManager.default.createDirectory(
                at: lockFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw DirectoryAuthorizationError.sharedStorageUnavailable
        }

        let descriptor = lockFileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        }
        guard descriptor >= 0 else {
            throw DirectoryAuthorizationError.sharedStorageUnavailable
        }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else {
                throw DirectoryAuthorizationError.sharedStorageUnavailable
            }
        }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}

nonisolated struct DirectoryAuthorizationConfiguration: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 3

    let schemaVersion: Int
    var records: [DirectoryAuthorizationRecord]

    init(
        schemaVersion: Int = currentSchemaVersion,
        records: [DirectoryAuthorizationRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.records = records
    }
}

nonisolated struct DirectoryAuthorizationRecord: Codable, Equatable, Sendable {
    let id: UUID
    var revision: UUID
    var path: String
    let volumePath: String?
    var applicationBookmark: Data
    var finderBookmark: Data?
    var handoffBookmark: Data?
    var finderStatus: DirectoryAuthorizationStatus
    var handoffAttempts: Int
    var handoffCreatedAt: Date

    init(
        id: UUID = UUID(),
        path: String,
        volumePath: String? = nil,
        applicationBookmark: Data,
        finderBookmark: Data?,
        handoffBookmark: Data?
    ) {
        self.id = id
        revision = UUID()
        self.path = path
        self.volumePath = volumePath
        self.applicationBookmark = applicationBookmark
        self.finderBookmark = finderBookmark
        self.handoffBookmark = handoffBookmark
        finderStatus = .waitingForExtension
        handoffAttempts = 1
        handoffCreatedAt = Date()
    }

    func shouldRenewHandoff(retryPending: Bool, now: Date = Date()) -> Bool {
        guard finderStatus != .ready else { return false }
        if retryPending {
            return true
        }
        return (finderStatus == .retryRequired || finderStatus == .unavailable)
            && handoffAttempts < 3
            && now.timeIntervalSince(handoffCreatedAt) >= 5
    }
}
