import Foundation

nonisolated struct FinderRuntimeLog: Sendable {
    private let logger: RuntimeLogger

    init(subsystem: String) {
        logger = RuntimeLogger(source: .finderExtension, subsystem: subsystem)
    }

    func started() {
        logger.notice(
            category: .lifecycle,
            event: .finderStarted,
            message: String(localized: "log.finder.started")
        )
    }

    func targetUnavailable(_ error: Error) {
        logger.error(
            category: .finderMenu,
            event: .finderTargetUnavailable,
            message: String(localized: "log.finder.current-folder-unavailable"),
            error: error
        )
    }

    func authorizationLoadFailed(_ error: Error) {
        logger.error(
            category: .finderMenu,
            event: .finderAuthorizationLoadFailed,
            message: String(localized: "log.finder.authorization-read-failed"),
            error: error
        )
    }

    func authorizationsPrepared(count: Int) {
        logger.notice(
            category: .authorization,
            event: .finderAuthorizationsPrepared,
            message: String(localized: "log.finder.authorizations-prepared"),
            fields: [.init(name: .count, value: String(count))]
        )
    }

    func authorizationPreparationFailed(_ error: Error, path: String? = nil) {
        logger.error(
            category: .authorization,
            event: .finderAuthorizationPreparationFailed,
            message: String(localized: "log.finder.authorization-prepare-failed"),
            error: error,
            fields: path.map { [.init(name: .path, value: $0)] } ?? []
        )
    }

    func targetUnauthorized(path: String) {
        logger.warning(
            category: .finderMenu,
            event: .finderTargetUnauthorized,
            message: String(localized: "log.finder.current-folder-unauthorized"),
            fields: [.init(name: .path, value: path)]
        )
    }

    func templatesLoadFailed(_ error: Error) {
        logger.error(
            category: .finderMenu,
            event: .finderTemplatesLoadFailed,
            message: String(localized: "log.finder.templates-read-failed"),
            error: error
        )
    }

    func menuResolutionFailed(identifier: Int, error: Error) {
        logger.error(
            category: .finderMenu,
            event: .finderMenuResolutionFailed,
            message: String(localized: "log.finder.menu-resolve-failed"),
            error: error,
            fields: [.init(name: .identifier, value: String(identifier))]
        )
    }

    func creationRequested(template: String, targetPath: String) {
        logger.debug(
            category: .fileCreation,
            event: .finderCreationRequested,
            message: String(localized: "log.finder.creation-requested"),
            fields: [
                .init(name: .template, value: template),
                .init(name: .path, value: targetPath)
            ]
        )
    }

    func creationSucceeded(path: String) {
        logger.notice(
            category: .fileCreation,
            event: .finderCreationSucceeded,
            message: String(localized: "log.finder.creation-succeeded"),
            fields: [.init(name: .path, value: path)]
        )
    }

    func creationFailed(template: String, error: Error) {
        logger.error(
            category: .fileCreation,
            event: .finderCreationFailed,
            message: String(localized: "log.finder.creation-failed"),
            error: error,
            fields: [.init(name: .template, value: template)]
        )
    }

    func menuIdentifierConflict(template: String) {
        logger.error(
            category: .finderMenu,
            event: .finderMenuIdentifierConflict,
            message: String(localized: "log.finder.identifier-conflict"),
            fields: [.init(name: .template, value: template)]
        )
    }
}
