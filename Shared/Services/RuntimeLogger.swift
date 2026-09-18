import Foundation
import OSLog

nonisolated struct RuntimeLogger: Sendable {
    private let source: RuntimeLogSource
    private let store: RuntimeLogStore
    private let systemLogger: Logger

    init(
        source: RuntimeLogSource,
        store: RuntimeLogStore = .shared,
        subsystem: String = Bundle.main.bundleIdentifier ?? "Newer"
    ) {
        self.source = source
        self.store = store
        systemLogger = Logger(subsystem: subsystem, category: source.rawValue)
    }

    func debug(
        category: RuntimeLogCategory,
        event: RuntimeLogEvent,
        message: String,
        fields: [RuntimeLogField] = []
    ) {
        record(level: .debug, category: category, event: event, message: message, fields: fields)
    }

    func info(
        category: RuntimeLogCategory,
        event: RuntimeLogEvent,
        message: String,
        fields: [RuntimeLogField] = []
    ) {
        record(level: .info, category: category, event: event, message: message, fields: fields)
    }

    func notice(
        category: RuntimeLogCategory,
        event: RuntimeLogEvent,
        message: String,
        fields: [RuntimeLogField] = []
    ) {
        record(level: .notice, category: category, event: event, message: message, fields: fields)
    }

    func warning(
        category: RuntimeLogCategory,
        event: RuntimeLogEvent,
        message: String,
        fields: [RuntimeLogField] = []
    ) {
        record(level: .warning, category: category, event: event, message: message, fields: fields)
    }

    func error(
        category: RuntimeLogCategory,
        event: RuntimeLogEvent,
        message: String,
        error: Error,
        fields: [RuntimeLogField] = []
    ) {
        record(
            level: .error,
            category: category,
            event: event,
            message: message,
            fields: fields + [RuntimeLogField(name: .reason, value: error.localizedDescription)]
        )
    }

    func error(
        category: RuntimeLogCategory,
        event: RuntimeLogEvent,
        message: String,
        fields: [RuntimeLogField] = []
    ) {
        record(level: .error, category: category, event: event, message: message, fields: fields)
    }

    private func record(
        level: RuntimeLogLevel,
        category: RuntimeLogCategory,
        event: RuntimeLogEvent,
        message: String,
        fields: [RuntimeLogField]
    ) {
        let systemMessage = "[\(event.rawValue)] \(message)\(formatted(fields: fields))"
        switch level {
        case .debug: systemLogger.debug("\(systemMessage, privacy: .public)")
        case .info: systemLogger.info("\(systemMessage, privacy: .public)")
        case .notice: systemLogger.notice("\(systemMessage, privacy: .public)")
        case .warning: systemLogger.warning("\(systemMessage, privacy: .public)")
        case .error: systemLogger.error("\(systemMessage, privacy: .public)")
        }
        store.append(RuntimeLogEntry(
            level: level,
            source: source,
            category: category,
            event: event,
            message: message,
            fields: fields
        ))
    }

    private func formatted(fields: [RuntimeLogField]) -> String {
        guard !fields.isEmpty else { return "" }
        return " " + fields.map { "\($0.name.rawValue)=\($0.value)" }.joined(separator: " ")
    }
}
