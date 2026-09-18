import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    private static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "NewerFinder"
    private static let runtimeLog = FinderRuntimeLog(subsystem: bundleIdentifier)
    private static let creationQueue = DispatchQueue(
        label: "\(bundleIdentifier).file-creation",
        qos: .userInitiated
    )

    private let templateMapLock = NSLock()
    private var templateRelativePathByTag: [Int: String] = [:]
    private lazy var menuIcon: NSImage? = {
        let applicationURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard applicationURL.pathExtension == "app" else { return nil }
        let image = NSWorkspace.shared.icon(forFile: applicationURL.path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }()

    override init() {
        super.init()
        Self.runtimeLog.started()
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/", isDirectory: true)
        ]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForContainer || menuKind == .contextualMenuForItems else {
            return nil
        }
        let targetKind: FinderTargetKind = menuKind == .contextualMenuForContainer
            ? .container
            : .item

        let rootMenu = NSMenu(title: "")
        let newFileTitle = String(localized: "finder.menu.new-file")
        let newItem = NSMenuItem(title: newFileTitle, action: nil, keyEquivalent: "")
        newItem.image = menuIcon
        let newMenu = NSMenu(title: newFileTitle)
        rootMenu.autoenablesItems = false
        newMenu.autoenablesItems = false
        newItem.isEnabled = true

        func menuWithStatus(_ title: String) -> NSMenu {
            let statusItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            newMenu.addItem(statusItem)
            newItem.submenu = newMenu
            rootMenu.addItem(newItem)
            replaceTemplateMap(with: [:])
            return rootMenu
        }

        let targetDirectory: URL
        do {
            targetDirectory = try resolvedTargetDirectory(kind: targetKind)
        } catch {
            Self.runtimeLog.targetUnavailable(error)
            return menuWithStatus(String(localized: "finder.menu.current-folder-unavailable"))
        }

        let hasAuthorization: Bool
        do {
            hasAuthorization = try DirectoryAuthorizationStore.shared.hasAuthorization(
                containing: targetDirectory
            )
        } catch {
            Self.runtimeLog.authorizationLoadFailed(error)
            return menuWithStatus(String(localized: "finder.menu.authorization-unavailable"))
        }
        guard hasAuthorization else {
            Self.runtimeLog.targetUnauthorized(path: targetDirectory.path)
            return menuWithStatus(String(localized: "finder.menu.current-folder-unauthorized"))
        }

        let templates: [TemplateItem]
        do {
            templates = try TemplateCatalog.shared.snapshot().filter(\.isEnabled)
        } catch {
            Self.runtimeLog.templatesLoadFailed(error)
            return menuWithStatus(String(localized: "finder.menu.templates-unavailable"))
        }

        if templates.isEmpty {
            let emptyItem = NSMenuItem(
                title: String(localized: "finder.menu.no-templates"),
                action: nil,
                keyEquivalent: ""
            )
            emptyItem.isEnabled = false
            newMenu.addItem(emptyItem)
        }

        let templatesByTag = Dictionary(grouping: templates) {
            Self.menuTag(for: $0.relativePath)
        }
        let currentTemplateRelativePathByTag = templatesByTag.compactMapValues { matches in
            matches.count == 1 ? matches[0].relativePath : nil
        }
        add(
            TemplateEntry.make(from: templates),
            to: newMenu,
            uniqueRelativePathsByTag: currentTemplateRelativePathByTag,
            targetKind: targetKind
        )
        replaceTemplateMap(with: currentTemplateRelativePathByTag)

        newItem.submenu = newMenu
        rootMenu.addItem(newItem)
        return rootMenu
    }

    @objc private func createFromTemplateInContainer(_ sender: NSMenuItem) {
        createFromTemplate(sender, targetKind: .container)
    }

    @objc private func createFromTemplateForItem(_ sender: NSMenuItem) {
        createFromTemplate(sender, targetKind: .item)
    }

    private func createFromTemplate(_ sender: NSMenuItem, targetKind: FinderTargetKind) {
        let tag = sender.tag
        let relativePath: String
        let targetDirectory: URL
        do {
            relativePath = try resolvedTemplateRelativePath(for: tag)
            // Finder 上下文只在菜单回调及其动作中有效, 必须在异步创建前捕获
            targetDirectory = try resolvedTargetDirectory(kind: targetKind)
        } catch {
            Self.runtimeLog.menuResolutionFailed(identifier: tag, error: error)
            return
        }
        Self.runtimeLog.creationRequested(
            template: relativePath,
            targetPath: targetDirectory.path
        )
        Self.creationQueue.async {
            Self.performCreation(relativePath: relativePath, targetDirectory: targetDirectory)
        }
    }

    private nonisolated static func performCreation(
        relativePath: String,
        targetDirectory: URL
    ) {
        do {
            let targetAccess = try DirectoryAuthorizationStore.shared.beginAccess(
                containing: targetDirectory
            )
            let createdURL = try withExtendedLifetime(targetAccess) {
                try FileCreationService.shared.createFile(
                    fromTemplateAtRelativePath: relativePath,
                    in: targetDirectory
                )
            }
            Self.runtimeLog.creationSucceeded(path: createdURL.path)
        } catch {
            runtimeLog.creationFailed(template: relativePath, error: error)
        }
    }

    private func resolvedTargetDirectory(kind: FinderTargetKind) throws -> URL {
        let controller = FIFinderSyncController.default()
        return try FinderTargetResolver.resolve(
            targetedURL: controller.targetedURL(),
            selectedItemURLs: controller.selectedItemURLs(),
            kind: kind
        )
    }

    private func add(
        _ entries: [TemplateEntry],
        to menu: NSMenu,
        uniqueRelativePathsByTag: [Int: String],
        targetKind: FinderTargetKind
    ) {
        for entry in entries {
            switch entry {
            case let .directory(_, name, children):
                let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: name)
                add(
                    children,
                    to: submenu,
                    uniqueRelativePathsByTag: uniqueRelativePathsByTag,
                    targetKind: targetKind
                )
                item.submenu = submenu
                menu.addItem(item)
            case let .template(template):
                let tag = Self.menuTag(for: template.relativePath)
                let item = NSMenuItem(
                    title: template.menuDisplayName,
                    action: targetKind == .container
                        ? #selector(createFromTemplateInContainer(_:))
                        : #selector(createFromTemplateForItem(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                // Finder 会跨进程复制扩展返回的菜单
                // representedObject 无法稳定传递, 实际点击时可能已经变为 nil
                // 相对路径生成的整数 tag 会保留, 新扩展实例可据此重新解析同一模板
                item.tag = tag
                if uniqueRelativePathsByTag[tag] == template.relativePath {
                    item.isEnabled = true
                } else {
                    item.isEnabled = false
                    Self.runtimeLog.menuIdentifierConflict(template: template.relativePath)
                }
                menu.addItem(item)
            }
        }
    }

    private func replaceTemplateMap(with map: [Int: String]) {
        templateMapLock.lock()
        templateRelativePathByTag = map
        templateMapLock.unlock()
    }

    private func templateRelativePath(for tag: Int) -> String? {
        templateMapLock.lock()
        defer { templateMapLock.unlock() }
        return templateRelativePathByTag[tag]
    }

    private func resolvedTemplateRelativePath(for tag: Int) throws -> String {
        if let relativePath = templateRelativePath(for: tag) {
            return relativePath
        }

        // Finder 可能在动作执行前重新创建扩展实例
        // 这里只接受唯一匹配的稳定标识, 避免列表变化后创建错误的模板
        let templates = try TemplateCatalog.shared.snapshot().filter(\.isEnabled)
        let matches = templates.filter { Self.menuTag(for: $0.relativePath) == tag }
        guard matches.count == 1, let template = matches.first else {
            throw FileCreationError.invalidTemplatePath
        }
        return template.relativePath
    }

    private nonisolated static func menuTag(for relativePath: String) -> Int {
        // 使用固定的 64 位 FNV-1a, 避免 Swift 随机 Hashable 导致跨进程结果变化
        var hash: UInt64 = 14695981039346656037
        for byte in relativePath.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return Int(hash & UInt64(Int.max))
    }
}
