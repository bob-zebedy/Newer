import Darwin
import Foundation

nonisolated enum UserPaths {
    static let appGroupIdentifier: String = {
        guard let identifier = Bundle.main.object(
            forInfoDictionaryKey: "NewerAppGroupIdentifier"
        ) as? String, !identifier.isEmpty else {
            preconditionFailure("App Group identifier is unavailable")
        }
        return identifier
    }()

    /// App Sandbox 会把 `homeDirectoryForCurrentUser` 重定向到容器目录
    /// Finder Sync 需要监听并读取真实登录用户目录, 因此从用户数据库解析 home
    static let homeDirectory: URL = {
        guard let passwordEntry = getpwuid(getuid()),
              let homePath = passwordEntry.pointee.pw_dir else {
            return FileManager.default.homeDirectoryForCurrentUser
        }

        return URL(
            fileURLWithPath: String(cString: homePath),
            isDirectory: true
        )
    }()

    static let appGroupContainer: URL = {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            preconditionFailure("App Group container is unavailable")
        }
        return container
    }()

    static let templateDirectory = appGroupContainer
        .appendingPathComponent("Templates", isDirectory: true)

    static let configurationFile = appGroupContainer
        .appendingPathComponent("configuration.json", isDirectory: false)

    static let directoryAuthorizationsFile = appGroupContainer
        .appendingPathComponent("directory-authorizations.plist", isDirectory: false)

    static let directoryAuthorizationsLockFile = appGroupContainer
        .appendingPathComponent("directory-authorizations.lock", isDirectory: false)

    static let runtimeLogFile = appGroupContainer
        .appendingPathComponent("runtime.log", isDirectory: false)
}
