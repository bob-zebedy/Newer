import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: TemplateSettingsModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: SettingsPage = .permissions

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection)

            Group {
                switch selection {
                case .permissions:
                    PermissionSettingsView(model: model)
                case .templates:
                    TemplateSettingsView(model: model)
                case .logs:
                    RuntimeLogSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshAuthorization()
                model.refresh()
            }
        }
        .task {
            await model.monitorExtensionStatus()
        }
    }
}

private enum SettingsPage: CaseIterable, Identifiable {
    case permissions
    case templates
    case logs

    var id: Self {
        self
    }

    var title: LocalizedStringKey {
        switch self {
        case .permissions: "settings.sidebar.permissions"
        case .templates: "settings.sidebar.templates"
        case .logs: "settings.sidebar.logs"
        }
    }

    var symbolName: String {
        switch self {
        case .permissions: "key.fill"
        case .templates: "doc.on.doc"
        case .logs: "list.bullet.rectangle"
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPage

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Newer")
                        .font(.headline)

                    Text(versionBuildText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 8)

            VStack(spacing: 4) {
                ForEach(SettingsPage.allCases) { page in
                    Button {
                        selection = page
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: page.symbolName)
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 20)
                            Text(page.title)
                                .font(.callout.weight(selection == page ? .semibold : .regular))
                            Spacer()
                        }
                        .foregroundStyle(selection == page ? Color.accentColor : Color.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background {
                            if selection == page {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.accentColor.opacity(0.13))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(14)
        .frame(width: 166)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private var versionBuildText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return String(
            format: String(localized: "settings.sidebar.version-build"),
            version,
            build
        )
    }
}
