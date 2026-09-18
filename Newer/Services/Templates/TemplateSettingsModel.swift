import AppKit
import Combine
import FinderSync
import Foundation
import Security
import SwiftUI

@MainActor
final class TemplateSettingsModel: ObservableObject {
    @Published var items: [TemplateItem] = []
    @Published private(set) var extensionStatus: FinderExtensionStatus = .needsConfirmation
    @Published private(set) var authorizedDirectories: [AuthorizedDirectory] = []

    private let catalog: TemplateCatalog
    private let authorizationStore: DirectoryAuthorizationStore
    private let runtimeLog: ApplicationRuntimeLog
    private var scheduledTemplateRefresh: Task<Void, Never>?
    private var authorizationRefresh: Task<Void, Never>?
    private var retryPendingAuthorizations = true
    private var authorizationRefreshRequested = false
    private var lastAuthorizationLoadError: String?
    private lazy var templateDirectoryMonitor = TemplateDirectoryMonitor { [weak self] in
        self?.scheduleTemplateRefresh()
    }

    private static var finderExtensionBundleIdentifier: String? {
        Bundle.main.bundleIdentifier.map { "\($0).finder" }
    }

    init(
        catalog: TemplateCatalog = .shared,
        authorizationStore: DirectoryAuthorizationStore = .shared,
        runtimeLogger: RuntimeLogger = RuntimeLogger(source: .application)
    ) {
        self.catalog = catalog
        self.authorizationStore = authorizationStore
        runtimeLog = ApplicationRuntimeLog(logger: runtimeLogger)
        runtimeLog.applicationStarted()
        refresh()
        refreshAuthorization()
    }

    func refresh() {
        do {
            templateDirectoryMonitor.startMonitoring(catalog.templateDirectory)
            let refreshed = try catalog.snapshot()
            if refreshed != items {
                items = refreshed
                try save()
                runtimeLog.templatesLoaded(count: items.count)
            }
        } catch {
            runtimeLog.templatesLoadFailed(error)
        }
        refreshExtensionStatus()
    }

    func authorizeDirectory() {
        requestAuthorization(
            initialDirectory: UserPaths.homeDirectory,
            title: String(localized: "settings.permissions.file-access.panel.directory.title"),
            message: String(localized: "settings.permissions.file-access.panel.directory.message")
        )
    }

    func authorizeExternalDisk() {
        requestAuthorization(
            initialDirectory: URL(fileURLWithPath: "/Volumes", isDirectory: true),
            title: String(localized: "settings.permissions.file-access.panel.external-disk.title"),
            message: String(localized: "settings.permissions.file-access.panel.external-disk.message"),
            validate: { url in
                let normalizedURL = url.resolvingSymlinksInPath().standardizedFileURL
                let volumesURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
                guard normalizedURL.deletingLastPathComponent() == volumesURL else {
                    throw ExternalDiskAuthorizationError.selectVolumeRoot
                }
                return url
            }
        )
    }

    func removeDirectoryAuthorization(_ directory: AuthorizedDirectory) {
        let store = authorizationStore
        Task { [weak self] in
            do {
                try await Task.detached { try store.removeAuthorization(id: directory.id) }.value
                self?.authorizedDirectories.removeAll { $0.id == directory.id }
                self?.runtimeLog.authorizationRemoved(path: directory.path)
                self?.refreshAuthorization()
            } catch {
                self?.runtimeLog.authorizationRemoveFailed(error)
            }
        }
    }

    func update(_ item: TemplateItem) {
        guard let index = items.firstIndex(where: { $0.relativePath == item.relativePath }) else {
            return
        }
        var updated = items[index]
        updated.displayName = item.displayName
        updated.isEnabled = item.isEnabled
        guard updated != items[index] else { return }
        items[index] = updated
        runtimeLog.templateUpdated(path: updated.relativePath)
        persistChanges()
    }

    func setEnabled(_ isEnabled: Bool, for entry: TemplateEntry) {
        let templatePaths = Set(entry.flattenedTemplates.map(\.relativePath))
        guard !templatePaths.isEmpty else { return }

        var updated = items
        for index in updated.indices where templatePaths.contains(updated[index].relativePath) {
            updated[index].isEnabled = isEnabled
        }
        guard updated != items else { return }
        items = updated
        runtimeLog.templateSelectionUpdated(count: templatePaths.count)
        persistChanges()
    }

    func moveTemplateEntries(
        within parentRelativePath: String,
        fromOffsets offsets: IndexSet,
        toOffset destination: Int
    ) {
        var hierarchy = TemplateEntry.make(from: items)
        guard var siblings = TemplateEntry.entries(
            in: hierarchy,
            parentRelativePath: parentRelativePath
        ) else { return }
        guard !offsets.isEmpty,
              offsets.allSatisfy({ siblings.indices.contains($0) }),
              (0 ... siblings.count).contains(destination) else {
            return
        }

        let originalSiblings = siblings
        siblings.move(fromOffsets: offsets, toOffset: destination)
        guard siblings != originalSiblings,
              TemplateEntry.replaceEntries(
                  in: &hierarchy,
                  parentRelativePath: parentRelativePath,
                  with: siblings
              ) else { return }

        items = hierarchy.flatMap(\.flattenedTemplates)
        runtimeLog.templatesReordered()
        persistChanges()
    }

    func openTemplateDirectory() {
        do {
            try catalog.ensureTemplateDirectoryExists()
            NSWorkspace.shared.open(catalog.templateDirectory)
            runtimeLog.templateDirectoryOpened()
        } catch {
            runtimeLog.templateDirectoryOpenFailed(error)
        }
    }

    func showExtensionSettings() {
        runtimeLog.extensionSettingsOpened()
        FIFinderSyncController.showExtensionManagementInterface()
    }
}

extension TemplateSettingsModel {
    func refreshAuthorization() {
        authorizationRefreshRequested = true
        guard authorizationRefresh == nil else { return }
        let shouldRetry = retryPendingAuthorizations
        retryPendingAuthorizations = false
        authorizationRefreshRequested = false
        let store = authorizationStore
        authorizationRefresh = Task { [weak self] in
            do {
                let refreshed = try await Task.detached {
                    try store.authorizedDirectories(retryPending: shouldRetry)
                }.value
                guard let self else { return }
                lastAuthorizationLoadError = nil
                if refreshed != authorizedDirectories {
                    authorizedDirectories = refreshed
                    runtimeLog.authorizationsLoaded(count: refreshed.count)
                }
            } catch {
                if self?.lastAuthorizationLoadError != error.localizedDescription {
                    self?.runtimeLog.authorizationsLoadFailed(error)
                }
                self?.lastAuthorizationLoadError = error.localizedDescription
            }
            self?.authorizationRefresh = nil
            if self?.authorizationRefreshRequested == true {
                self?.refreshAuthorization()
            }
        }
    }

    private func requestAuthorization(
        initialDirectory: URL,
        title: String,
        message: String,
        validate: @escaping (URL) throws -> URL = { $0 }
    ) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = String(localized: "settings.permissions.file-access.panel.authorize")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = initialDirectory

        panel.begin { [weak self] response in
            guard response == .OK, let directoryURL = panel.url else { return }
            Task { @MainActor [weak self] in
                defer { directoryURL.stopAccessingSecurityScopedResource() }
                guard let self else { return }
                do {
                    let validatedURL = try validate(directoryURL)
                    let store = authorizationStore
                    try await Task.detached { try store.saveAuthorization(for: validatedURL) }.value
                    runtimeLog.authorizationAdded(path: validatedURL.path)
                    refresh()
                    refreshAuthorization()
                } catch {
                    runtimeLog.authorizationAddFailed(error)
                }
            }
        }
    }
}

extension TemplateSettingsModel {
    private func scheduleTemplateRefresh() {
        scheduledTemplateRefresh?.cancel()
        scheduledTemplateRefresh = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func persistChanges() {
        do {
            try save()
        } catch {
            runtimeLog.templatesSaveFailed(error)
        }
    }

    private func save() throws {
        try catalog.save(items)
    }
}

extension TemplateSettingsModel {
    func refreshExtensionStatus() {
        let refreshedStatus = Self.extensionStatus(
            isSystemEnabled: FIFinderSyncController.isExtensionEnabled,
            isRunning: isFinderExtensionRunning,
            hasDevelopmentTeamIdentifier: hasDevelopmentTeamIdentifier
        )
        guard refreshedStatus != extensionStatus else { return }
        extensionStatus = refreshedStatus
        runtimeLog.extensionStatusChanged(status: refreshedStatus.logDescription)
    }

    static func extensionStatus(
        isSystemEnabled: Bool,
        isRunning: Bool,
        hasDevelopmentTeamIdentifier: Bool
    ) -> FinderExtensionStatus {
        if hasDevelopmentTeamIdentifier {
            return isSystemEnabled ? .enabled : .disabled
        }

        // Sign to Run Locally 使用临时签名, 宿主 App 无法稳定关联 Finder 扩展
        // 此时运行状态只用于确认扩展已经启动
        return isRunning ? .enabled : .needsConfirmation
    }

    func monitorExtensionStatus() async {
        while !Task.isCancelled {
            refreshExtensionStatus()
            refreshAuthorization()
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
        }
    }

    private var isFinderExtensionRunning: Bool {
        guard let bundleIdentifier = Self.finderExtensionBundleIdentifier else { return false }
        return !NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).isEmpty
    }

    private var hasDevelopmentTeamIdentifier: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.team-identifier" as CFString,
            nil
        ) is String
    }
}

private enum ExternalDiskAuthorizationError: LocalizedError {
    case selectVolumeRoot

    var errorDescription: String? {
        String(localized: "settings.permissions.file-access.panel.external-disk.invalid-selection")
    }
}

private extension FinderExtensionStatus {
    var logDescription: String {
        switch self {
        case .enabled: String(localized: "settings.permissions.finder-extension.status.enabled")
        case .disabled: String(localized: "settings.permissions.finder-extension.status.disabled")
        case .needsConfirmation: String(localized: "settings.permissions.finder-extension.status.needs-confirmation")
        }
    }
}
