import Darwin
import Foundation

nonisolated enum FileCreationError: LocalizedError {
    case invalidTemplatePath
    case templateNotFound(String)
    case targetIsNotDirectory(String)
    case unableToChooseUniqueName(String)

    var errorDescription: String? {
        switch self {
        case .invalidTemplatePath:
            String(localized: "error.file-creation.invalid-template-path")
        case let .templateNotFound(name):
            String.localizedStringWithFormat(
                String(localized: "error.file-creation.template-not-found"),
                name
            )
        case let .targetIsNotDirectory(path):
            String.localizedStringWithFormat(
                String(localized: "error.file-creation.target-not-directory"),
                path
            )
        case let .unableToChooseUniqueName(name):
            String.localizedStringWithFormat(
                String(localized: "error.file-creation.unique-name-unavailable"),
                name
            )
        }
    }
}

nonisolated struct FileCreationService {
    private static let temporaryDirectoryPrefix = ".newer-"
    private static let temporaryDirectorySuffix = ".tmp"
    private static let ownershipFileName = ".newer-owner"
    private static let ownershipHeader = "Newer temporary copy\n"

    let templateDirectory: URL

    static var shared: FileCreationService {
        FileCreationService(
            templateDirectory: TemplateCatalog.shared.templateDirectory
        )
    }

    func createFile(
        fromTemplateAtRelativePath relativePath: String,
        in targetDirectory: URL
    ) throws -> URL {
        try validateDirectory(targetDirectory)

        let template = try TemplateLocation(
            relativePath: relativePath,
            templateDirectory: templateDirectory
        )
        let templateURL = template.url
        let fileName = template.fileName
        let values = try? templateURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
            throw FileCreationError.templateNotFound(relativePath)
        }

        removeAbandonedTemporaryDirectories(in: targetDirectory)
        let temporaryCopy = try createTemporaryDirectory(in: targetDirectory)
        defer {
            try? FileManager.default.removeItem(at: temporaryCopy.url)
            try? temporaryCopy.lockFile.close()
        }

        let temporaryFile = temporaryCopy.url.appendingPathComponent(
            fileName,
            isDirectory: false
        )
        // FileManager 会在支持的 APFS 同卷场景自动使用 CoW 克隆
        // 其他文件系统会回退为普通复制
        try FileManager.default.copyItem(at: templateURL, to: temporaryFile)
        return try publish(
            temporaryFile,
            in: targetDirectory,
            desiredFileName: fileName
        )
    }

    private func createTemporaryDirectory(in targetDirectory: URL) throws -> TemporaryCopyDirectory {
        let identifier = UUID()
        let directory = targetDirectory.appendingPathComponent(
            "\(Self.temporaryDirectoryPrefix)\(identifier.uuidString)\(Self.temporaryDirectorySuffix)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)

        let ownershipFile = directory.appendingPathComponent(
            Self.ownershipFileName,
            isDirectory: false
        )
        guard FileManager.default.createFile(
            atPath: ownershipFile.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            try? FileManager.default.removeItem(at: directory)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let lockFile: FileHandle
        do {
            lockFile = try FileHandle(forUpdating: ownershipFile)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }

        do {
            guard flock(lockFile.fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            let marker = Data(Self.ownershipMarker(for: identifier).utf8)
            try lockFile.write(contentsOf: marker)
            try lockFile.synchronize()
            return TemporaryCopyDirectory(
                url: directory,
                lockFile: lockFile
            )
        } catch {
            try? lockFile.close()
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private func removeAbandonedTemporaryDirectories(in targetDirectory: URL) {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: targetDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return
        }

        for directory in items {
            guard let identifier = Self.temporaryDirectoryIdentifier(for: directory) else {
                continue
            }
            let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else {
                continue
            }

            let ownershipFile = directory.appendingPathComponent(
                Self.ownershipFileName,
                isDirectory: false
            )
            let ownershipValues = try? ownershipFile.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard ownershipValues?.isRegularFile == true,
                  ownershipValues?.isSymbolicLink != true,
                  let marker = try? Data(contentsOf: ownershipFile),
                  marker == Data(Self.ownershipMarker(for: identifier).utf8),
                  let lockFile = try? FileHandle(forReadingFrom: ownershipFile) else {
                continue
            }

            defer { try? lockFile.close() }
            guard flock(lockFile.fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
                continue
            }
            guard let lockedMarker = try? lockFile.readToEnd(),
                  lockedMarker == marker else {
                continue
            }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func temporaryDirectoryIdentifier(for url: URL) -> UUID? {
        let name = url.lastPathComponent
        guard name.hasPrefix(temporaryDirectoryPrefix),
              name.hasSuffix(temporaryDirectorySuffix) else {
            return nil
        }
        let start = name.index(name.startIndex, offsetBy: temporaryDirectoryPrefix.count)
        let end = name.index(name.endIndex, offsetBy: -temporaryDirectorySuffix.count)
        return UUID(uuidString: String(name[start ..< end]))
    }

    private static func ownershipMarker(for identifier: UUID) -> String {
        "\(ownershipHeader)\(identifier.uuidString)\n"
    }

    private func publish(
        _ temporaryFile: URL,
        in directory: URL,
        desiredFileName: String
    ) throws -> URL {
        for index in 1 ... 10000 {
            let candidate = destination(
                in: directory,
                desiredFileName: desiredFileName,
                index: index
            )
            switch try moveExclusively(temporaryFile, to: candidate) {
            case .moved:
                return candidate
            case .destinationExists:
                continue
            }
        }

        throw FileCreationError.unableToChooseUniqueName(desiredFileName)
    }

    private func destination(
        in directory: URL,
        desiredFileName: String,
        index: Int
    ) -> URL {
        guard index > 1 else {
            return directory.appendingPathComponent(desiredFileName, isDirectory: false)
        }

        let desiredURL = directory.appendingPathComponent(desiredFileName, isDirectory: false)
        let extensionName = desiredURL.pathExtension
        let baseName = extensionName.isEmpty
            ? desiredURL.lastPathComponent
            : desiredURL.deletingPathExtension().lastPathComponent
        let candidateName = if extensionName.isEmpty {
            "\(baseName) \(index)"
        } else {
            "\(baseName) \(index).\(extensionName)"
        }
        return directory.appendingPathComponent(candidateName, isDirectory: false)
    }

    private func moveExclusively(_ source: URL, to destination: URL) throws -> ExclusiveMoveResult {
        let renameResult = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                renamex_np(sourcePath, destinationPath, UInt32(RENAME_EXCL))
            }
        }
        if renameResult == 0 {
            return .moved
        }

        let renameError = errno
        if renameError == EEXIST {
            return .destinationExists
        }
        guard renameError == ENOTSUP || renameError == EINVAL || renameError == ENOSYS else {
            throw POSIXError(POSIXErrorCode(rawValue: renameError) ?? .EIO)
        }

        // 少数不支持 RENAME_EXCL 的文件系统先尝试独占硬链接, 避免再次复制
        let linkResult = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                link(sourcePath, destinationPath)
            }
        }
        if linkResult == 0 {
            try? FileManager.default.removeItem(at: source)
            return .moved
        }
        if errno == EEXIST {
            return .destinationExists
        }

        // 最后交给 Foundation 执行同卷移动, 其契约同样是不覆盖既有目标
        // 临时文件和最终文件位于同一目录层级, 因此不会退化成跨卷复制
        do {
            try FileManager.default.moveItem(at: source, to: destination)
            return .moved
        } catch {
            if Self.isDestinationExistsError(error) {
                return .destinationExists
            }
            throw error
        }
    }

    private static func isDestinationExistsError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EEXIST) {
            return true
        }
        return nsError.domain == NSCocoaErrorDomain
            && nsError.code == CocoaError.fileWriteFileExists.rawValue
    }

    private func validateDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FileCreationError.targetIsNotDirectory(url.path)
        }
    }
}

private nonisolated enum ExclusiveMoveResult {
    case moved
    case destinationExists
}

private nonisolated struct TemplateLocation {
    let url: URL
    let fileName: String

    init(relativePath: String, templateDirectory: URL) throws {
        guard let components = TemplateItem.pathComponents(for: relativePath),
              let fileName = components.last else {
            throw FileCreationError.invalidTemplatePath
        }

        let url = components.reduce(templateDirectory) { directory, component in
            directory.appendingPathComponent(component, isDirectory: false)
        }
        let resolvedRoot = templateDirectory.resolvingSymlinksInPath().standardizedFileURL
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard SecurityScopedDirectoryAccess.contains(resolvedURL, in: resolvedRoot),
              resolvedURL != resolvedRoot else {
            throw FileCreationError.invalidTemplatePath
        }

        self.url = url
        self.fileName = fileName
    }
}

private nonisolated struct TemporaryCopyDirectory {
    let url: URL
    let lockFile: FileHandle
}
