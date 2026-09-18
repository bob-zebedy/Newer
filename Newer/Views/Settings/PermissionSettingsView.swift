import SwiftUI

struct PermissionSettingsView: View {
    @ObservedObject var model: TemplateSettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                finderExtensionSection
                fileAccessSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var finderExtensionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionTitle(title: "settings.permissions.finder-extension.title")

            SettingsSurfaceCard {
                HStack(spacing: 14) {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(extensionStatusColor)
                        .frame(width: 40, height: 40)
                        .background(extensionStatusColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))

                    HStack(spacing: 8) {
                        Text("settings.permissions.finder-extension.name")
                            .font(.headline)
                        SettingsStatusBadge(color: extensionStatusColor, title: extensionStatusTitle)
                    }

                    Spacer(minLength: 8)

                    Button("settings.permissions.finder-extension.open-settings") {
                        model.showExtensionSettings()
                    }
                }
                .padding(16)
            }
        }
    }

    private var fileAccessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                SettingsSectionTitle(title: "settings.permissions.file-access.title")

                Spacer()
                authorizationMenu
            }

            SettingsSurfaceCard {
                if model.authorizedDirectories.isEmpty {
                    HStack(spacing: 14) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 23))
                            .foregroundStyle(.secondary)
                            .frame(width: 32)

                        Text("settings.permissions.file-access.empty.title")
                            .font(.headline)

                        Spacer()
                    }
                    .padding(16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.authorizedDirectories.enumerated()), id: \.element.id) { index, directory in
                            AuthorizedDirectoryRow(
                                directory: directory,
                                isFinderExtensionDisabled: model.extensionStatus == .disabled
                            ) {
                                model.removeDirectoryAuthorization(directory)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(
                                directory.isAvailable
                                    ? Color.green.opacity(0.14)
                                    : Color.orange.opacity(0.16)
                            )

                            if index < model.authorizedDirectories.count - 1 {
                                Divider()
                                    .padding(.leading, 52)
                            }
                        }
                    }
                }
            }
        }
    }

    private var authorizationMenu: some View {
        Menu {
            Button {
                model.authorizeDirectory()
            } label: {
                Label("settings.permissions.file-access.directory", systemImage: "folder")
            }

            Button {
                model.authorizeExternalDisk()
            } label: {
                Label("settings.permissions.file-access.external-disk", systemImage: "externaldrive")
            }
        } label: {
            Label("settings.permissions.file-access.add-location", systemImage: "plus")
                .font(.callout.weight(.medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var extensionStatusTitle: String {
        switch model.extensionStatus {
        case .enabled: String(localized: "settings.permissions.finder-extension.status.enabled")
        case .disabled: String(localized: "settings.permissions.finder-extension.status.disabled")
        case .needsConfirmation: String(localized: "settings.permissions.finder-extension.status.needs-confirmation")
        }
    }

    private var extensionStatusColor: Color {
        switch model.extensionStatus {
        case .enabled: .green
        case .disabled: .orange
        case .needsConfirmation: .secondary
        }
    }
}
