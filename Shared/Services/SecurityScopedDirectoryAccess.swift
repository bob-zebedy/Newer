import Foundation

nonisolated enum SecurityScopedDirectoryAccessError: Error {
    case accessDenied
}

final nonisolated class SecurityScopedDirectoryAccess {
    let directoryURL: URL
    private let isAccessing: Bool

    init(directoryURL: URL) throws {
        self.directoryURL = directoryURL
        isAccessing = directoryURL.startAccessingSecurityScopedResource()
        guard isAccessing else {
            throw SecurityScopedDirectoryAccessError.accessDenied
        }
    }

    deinit {
        if isAccessing {
            directoryURL.stopAccessingSecurityScopedResource()
        }
    }

    static func contains(_ candidateURL: URL, in directoryURL: URL) -> Bool {
        let rootPath = directoryURL.resolvingSymlinksInPath().standardizedFileURL.path
        let candidatePath = candidateURL.resolvingSymlinksInPath().standardizedFileURL.path

        if rootPath == "/" {
            return true
        }
        if candidatePath == rootPath {
            return true
        }
        return candidatePath.hasPrefix(rootPath + "/")
    }

    static func containsOnSameFileSystem(
        _ candidateURL: URL,
        in directoryURL: URL,
        deviceIdentifier: (URL) -> UInt64?
    ) -> Bool {
        guard contains(candidateURL, in: directoryURL),
              let directoryDevice = deviceIdentifier(directoryURL),
              let candidateDevice = deviceIdentifier(candidateURL) else {
            return false
        }
        return directoryDevice == candidateDevice
    }

    static func deviceIdentifier(for url: URL) -> UInt64? {
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolvedURL.path),
              let identifier = attributes[.systemNumber] as? NSNumber else { return nil }
        return identifier.uint64Value
    }
}
