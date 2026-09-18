import Foundation

nonisolated struct ApplicationRuntimeLog: Sendable {
    private let logger: RuntimeLogger

    init(logger: RuntimeLogger) {
        self.logger = logger
    }

    func applicationStarted() {
        logger.notice(
            category: .lifecycle,
            event: .applicationStarted,
            message: String(localized: "log.application.started")
        )
    }

    func templatesLoaded(count: Int) {
        logger.info(
            category: .templates,
            event: .templatesLoaded,
            message: String(localized: "log.templates.refreshed"),
            fields: [.init(name: .count, value: String(count))]
        )
    }

    func templatesLoadFailed(_ error: Error) {
        logger.error(
            category: .templates,
            event: .templatesLoadFailed,
            message: String(localized: "log.templates.refresh-failed"),
            error: error
        )
    }

    func authorizationRemoved(path: String) {
        logger.notice(
            category: .authorization,
            event: .authorizationRemoved,
            message: String(localized: "log.authorization.removed"),
            fields: [.init(name: .path, value: path)]
        )
    }

    func authorizationRemoveFailed(_ error: Error) {
        logger.error(
            category: .authorization,
            event: .authorizationRemoveFailed,
            message: String(localized: "log.authorization.remove-failed"),
            error: error
        )
    }

    func templateUpdated(path: String) {
        logger.info(
            category: .templates,
            event: .templateUpdated,
            message: String(localized: "log.templates.updated"),
            fields: [.init(name: .template, value: path)]
        )
    }

    func templateSelectionUpdated(count: Int) {
        logger.info(
            category: .templates,
            event: .templateSelectionUpdated,
            message: String(localized: "log.templates.selection-updated"),
            fields: [.init(name: .count, value: String(count))]
        )
    }

    func templatesReordered() {
        logger.info(
            category: .templates,
            event: .templatesReordered,
            message: String(localized: "log.templates.reordered")
        )
    }

    func templateDirectoryOpened() {
        logger.info(
            category: .templates,
            event: .templateDirectoryOpened,
            message: String(localized: "log.templates.directory-opened")
        )
    }

    func templateDirectoryOpenFailed(_ error: Error) {
        logger.error(
            category: .templates,
            event: .templateDirectoryOpenFailed,
            message: String(localized: "log.templates.directory-open-failed"),
            error: error
        )
    }

    func extensionSettingsOpened() {
        logger.info(
            category: .authorization,
            event: .extensionSettingsOpened,
            message: String(localized: "log.authorization.extension-settings-opened")
        )
    }

    func authorizationsLoaded(count: Int) {
        logger.info(
            category: .authorization,
            event: .authorizationsLoaded,
            message: String(localized: "log.authorization.refreshed"),
            fields: [.init(name: .count, value: String(count))]
        )
    }

    func authorizationsLoadFailed(_ error: Error) {
        logger.error(
            category: .authorization,
            event: .authorizationsLoadFailed,
            message: String(localized: "log.authorization.refresh-failed"),
            error: error
        )
    }

    func authorizationAdded(path: String) {
        logger.notice(
            category: .authorization,
            event: .authorizationAdded,
            message: String(localized: "log.authorization.added"),
            fields: [.init(name: .path, value: path)]
        )
    }

    func authorizationAddFailed(_ error: Error) {
        logger.error(
            category: .authorization,
            event: .authorizationAddFailed,
            message: String(localized: "log.authorization.add-failed"),
            error: error
        )
    }

    func templatesSaveFailed(_ error: Error) {
        logger.error(
            category: .templates,
            event: .templatesSaveFailed,
            message: String(localized: "log.templates.save-failed"),
            error: error
        )
    }

    func extensionStatusChanged(status: String) {
        logger.info(
            category: .authorization,
            event: .extensionStatusChanged,
            message: String(localized: "log.authorization.extension-status-changed"),
            fields: [.init(name: .status, value: status)]
        )
    }
}
