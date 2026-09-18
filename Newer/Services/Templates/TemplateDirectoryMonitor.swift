import CoreServices
import Foundation

@MainActor
final class TemplateDirectoryMonitor {
    private static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "Newer"
    private let eventQueue = DispatchQueue(
        label: "\(bundleIdentifier).template-directory-monitor",
        qos: .utility
    )
    private let onChange: @MainActor () -> Void
    private var monitoredDirectoryPath: String?
    private var stream: FSEventStreamRef?

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    isolated deinit {
        stopMonitoring()
    }

    func startMonitoring(_ directory: URL) {
        let path = directory.standardizedFileURL.path
        guard stream == nil || monitoredDirectoryPath != path else { return }
        stopMonitoring()

        let callbackBox = TemplateDirectoryMonitorCallbackBox { [weak self] in
            Task { @MainActor [weak self] in
                self?.onChange()
            }
        }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(callbackBox).toOpaque(),
            retain: retainTemplateDirectoryCallback,
            release: releaseTemplateDirectoryCallback,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagWatchRoot |
                kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            nil,
            handleTemplateDirectoryEvents,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            flags
        ) else { return }

        self.stream = stream
        monitoredDirectoryPath = path
        FSEventStreamSetDispatchQueue(stream, eventQueue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            monitoredDirectoryPath = nil
            return
        }
    }

    func stopMonitoring() {
        guard let stream else {
            monitoredDirectoryPath = nil
            return
        }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        monitoredDirectoryPath = nil
    }
}

private nonisolated func handleTemplateDirectoryEvents(
    _: ConstFSEventStreamRef,
    info: UnsafeMutableRawPointer?,
    _: Int,
    _: UnsafeMutableRawPointer,
    _: UnsafePointer<FSEventStreamEventFlags>,
    _: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    Unmanaged<TemplateDirectoryMonitorCallbackBox>
        .fromOpaque(info)
        .takeUnretainedValue()
        .notify()
}

private nonisolated func retainTemplateDirectoryCallback(
    _ info: UnsafeRawPointer?
) -> UnsafeRawPointer? {
    guard let info else { return nil }
    _ = Unmanaged<TemplateDirectoryMonitorCallbackBox>.fromOpaque(info).retain()
    return info
}

private nonisolated func releaseTemplateDirectoryCallback(_ info: UnsafeRawPointer?) {
    guard let info else { return }
    Unmanaged<TemplateDirectoryMonitorCallbackBox>.fromOpaque(info).release()
}

private final nonisolated class TemplateDirectoryMonitorCallbackBox: @unchecked Sendable {
    private let callback: @Sendable () -> Void

    init(callback: @escaping @Sendable () -> Void) {
        self.callback = callback
    }

    func notify() {
        callback()
    }
}
