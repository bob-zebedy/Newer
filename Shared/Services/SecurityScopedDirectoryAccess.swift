import Foundation

final nonisolated class SecurityScopedDirectoryAccess {
    let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    deinit {
        directoryURL.stopAccessingSecurityScopedResource()
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
        var candidate = url.resolvingSymlinksInPath().standardizedFileURL
        while true {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: candidate.path),
               let deviceIdentifier = attributes[.systemNumber] as? NSNumber {
                return deviceIdentifier.uint64Value
            }

            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { return nil }
            candidate = parent
        }
    }
}
