import Darwin
import Foundation

nonisolated struct RuntimeLogFileState: Equatable, Sendable {
    let size: UInt64
    let modificationDate: Date
}

nonisolated struct RuntimeLogStore: Sendable {
    static let shared = RuntimeLogStore(fileURL: UserPaths.runtimeLogFile)

    let fileURL: URL

    private let maximumFileSize = 5 * 1024 * 1024
    private let retainedFileSize = 3 * 1024 * 1024

    func append(_ entry: RuntimeLogEntry) {
        do {
            try withFileLock(operation: LOCK_EX) {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys]
                var data = try encoder.encode(entry)
                data.append(0x0A)
                try append(data)
                try trimIfNeeded()
            }
        } catch {
            return
        }
    }

    func entries() throws -> [RuntimeLogEntry] {
        try withFileLock(operation: LOCK_SH) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
            let data = try Data(contentsOf: fileURL)
            return data.split(separator: 0x0A).compactMap { line in
                decodeEntry(from: Data(line))
            }
        }
    }

    func fileState() -> RuntimeLogFileState? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber,
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }
        return RuntimeLogFileState(
            size: size.uint64Value,
            modificationDate: modificationDate
        )
    }

    func clear() throws {
        try withFileLock(operation: LOCK_EX) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            try Data().write(to: fileURL, options: .atomic)
        }
    }

    private func append(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = open(fileURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }

        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
                )
                guard written > 0 else { throw posixError() }
                offset += written
            }
        }
    }

    private func trimIfNeeded() throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? NSNumber,
              size.intValue > maximumFileSize else { return }

        let data = try Data(contentsOf: fileURL)
        let retainedData = data.suffix(retainedFileSize)
        guard let newlineIndex = retainedData.firstIndex(of: 0x0A) else {
            try Data().write(to: fileURL, options: .atomic)
            return
        }
        let firstCompleteEntry = retainedData.index(after: newlineIndex)
        try Data(retainedData[firstCompleteEntry...]).write(to: fileURL, options: .atomic)
    }

    private func decodeEntry(from data: Data) -> RuntimeLogEntry? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let entry = try? decoder.decode(RuntimeLogEntry.self, from: data) {
            return entry
        }

        decoder.dateDecodingStrategy = .deferredToDate
        return try? decoder.decode(RuntimeLogEntry.self, from: data)
    }

    private func withFileLock<Result>(
        operation: Int32,
        _ body: () throws -> Result
    ) throws -> Result {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let lockURL = fileURL.appendingPathExtension("lock")
        let descriptor = open(lockURL.path, O_RDWR | O_CREAT, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        guard flock(descriptor, operation) == 0 else { throw posixError() }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    private func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
