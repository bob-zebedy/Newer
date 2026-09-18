import Foundation

nonisolated enum RuntimeLogLevel: String, Codable, Sendable {
    case debug
    case info
    case notice
    case warning
    case error
}

nonisolated enum RuntimeLogSource: String, Codable, Sendable {
    case application
    case finderExtension
}

nonisolated enum RuntimeLogCategory: String, Codable, Sendable {
    case lifecycle
    case templates
    case authorization
    case finderMenu = "finder-menu"
    case fileCreation = "file-creation"
}

nonisolated enum RuntimeLogEvent: String, Codable, Sendable {
    case legacy = "legacy.message"
    case applicationStarted = "app.started"
    case templatesLoaded = "templates.loaded"
    case templatesLoadFailed = "templates.load-failed"
    case templateUpdated = "templates.updated"
    case templateSelectionUpdated = "templates.selection-updated"
    case templatesReordered = "templates.reordered"
    case templateDirectoryOpened = "templates.directory-opened"
    case templateDirectoryOpenFailed = "templates.directory-open-failed"
    case templatesSaveFailed = "templates.save-failed"
    case authorizationAdded = "authorization.added"
    case authorizationAddFailed = "authorization.add-failed"
    case authorizationRemoved = "authorization.removed"
    case authorizationRemoveFailed = "authorization.remove-failed"
    case authorizationsLoaded = "authorization.loaded"
    case authorizationsLoadFailed = "authorization.load-failed"
    case extensionSettingsOpened = "extension.settings-opened"
    case extensionStatusChanged = "extension.status-changed"
    case finderStarted = "finder.started"
    case finderTargetUnavailable = "finder.target-unavailable"
    case finderAuthorizationLoadFailed = "finder.authorization-load-failed"
    case finderAuthorizationsPrepared = "finder.authorizations-prepared"
    case finderAuthorizationPreparationFailed = "finder.authorization-prepare-failed"
    case finderTargetUnauthorized = "finder.target-unauthorized"
    case finderTemplatesLoadFailed = "finder.templates-load-failed"
    case finderMenuResolutionFailed = "finder.menu-resolution-failed"
    case finderCreationRequested = "finder.creation-requested"
    case finderCreationSucceeded = "finder.creation-succeeded"
    case finderCreationFailed = "finder.creation-failed"
    case finderMenuIdentifierConflict = "finder.menu-identifier-conflict"
}

nonisolated enum RuntimeLogFieldName: String, Codable, Sendable {
    case count
    case path
    case template
    case identifier
    case status
    case reason
}

nonisolated struct RuntimeLogField: Codable, Equatable, Sendable {
    let name: RuntimeLogFieldName
    let value: String
}

nonisolated struct RuntimeLogEntry: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let timestamp: Date
    let level: RuntimeLogLevel
    let source: RuntimeLogSource
    let category: RuntimeLogCategory
    let event: RuntimeLogEvent
    let message: String
    let fields: [RuntimeLogField]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: RuntimeLogLevel,
        source: RuntimeLogSource,
        category: RuntimeLogCategory,
        event: RuntimeLogEvent,
        message: String,
        fields: [RuntimeLogField] = []
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.source = source
        self.category = category
        self.event = event
        self.message = message
        self.fields = fields
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case timestamp
        case level
        case source
        case category
        case event
        case message
        case fields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        level = try container.decode(RuntimeLogLevel.self, forKey: .level)
        source = try container.decode(RuntimeLogSource.self, forKey: .source)
        category = try container.decodeIfPresent(RuntimeLogCategory.self, forKey: .category) ?? .lifecycle
        event = try container.decodeIfPresent(RuntimeLogEvent.self, forKey: .event) ?? .legacy
        message = try container.decode(String.self, forKey: .message)
        fields = try container.decodeIfPresent([RuntimeLogField].self, forKey: .fields) ?? []
    }
}
