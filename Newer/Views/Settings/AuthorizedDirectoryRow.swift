import SwiftUI

struct AuthorizedDirectoryRow: View {
    let directory: AuthorizedDirectory
    var isFinderExtensionDisabled = false
    let onRemove: () -> Void

    private var isExternalDisk: Bool {
        directory.path.hasPrefix("/Volumes/")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isExternalDisk ? "externaldrive.fill" : "folder.fill")
                .font(.system(size: 17))
                .foregroundStyle(
                    directory.isAvailable
                        ? (isExternalDisk ? Color.blue : Color.accentColor)
                        : Color.secondary
                )
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(directory.url.lastPathComponent.isEmpty ? directory.path : directory.url.lastPathComponent)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(directory.isAvailable ? Color.primary : Color.secondary)
                Text(directory.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let statusTitle {
                Text(statusTitle)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button(action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }

    private var statusTitle: String? {
        switch directory.status {
        case .unavailable:
            String(localized: "settings.permissions.file-access.unavailable")
        case .needsAuthorization:
            String(localized: "settings.permissions.file-access.needs-authorization")
        case .ready, .waitingForExtension, .retryRequired:
            isFinderExtensionDisabled
                ? String(localized: "settings.permissions.file-access.extension-disabled")
                : nil
        }
    }
}
