import Foundation

nonisolated struct ConfigurationStore: Sendable {
    let fileURL: URL

    static let shared = ConfigurationStore(
        fileURL: UserPaths.configurationFile
    )

    func load() throws -> NewerConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return NewerConfiguration()
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        let storedVersion = try decoder.decode(StoredConfigurationVersion.self, from: data).version
        guard storedVersion == NewerConfiguration.currentVersion else {
            return NewerConfiguration()
        }
        return try decoder.decode(NewerConfiguration.self, from: data)
    }

    func save(_ configuration: NewerConfiguration) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: fileURL, options: .atomic)
    }
}

private nonisolated struct StoredConfigurationVersion: Decodable {
    let version: Int
}
