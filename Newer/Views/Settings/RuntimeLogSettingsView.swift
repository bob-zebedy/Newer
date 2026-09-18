import SwiftUI

struct RuntimeLogSettingsView: View {
    @StateObject private var model = RuntimeLogModel()
    @State private var levelFilter: RuntimeLogLevelFilter = .all
    @State private var sourceFilter: RuntimeLogSourceFilter = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            controls

            SettingsSurfaceCard {
                logContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await model.monitor()
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Text("settings.logs.title")
                .font(.callout.weight(.medium))

            HStack(spacing: 5) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text("settings.logs.live")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Picker("settings.logs.level-filter", selection: $levelFilter) {
                ForEach(RuntimeLogLevelFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 116)

            Menu {
                ForEach(RuntimeLogSourceFilter.allCases) { filter in
                    Button {
                        sourceFilter = filter
                    } label: {
                        if sourceFilter == filter {
                            Label(filter.title, systemImage: "checkmark")
                        } else {
                            Text(filter.title)
                        }
                    }
                }
            } label: {
                Label(sourceFilter.title, systemImage: "line.3.horizontal.decrease")
            }
            .fixedSize()

            Button {
                model.clear()
            } label: {
                Label("settings.logs.clear", systemImage: "trash")
            }
            .disabled(model.entries.isEmpty)
        }
    }

    @ViewBuilder
    private var logContent: some View {
        if displayedEntries.isEmpty {
            ContentUnavailableView(
                model.entries.isEmpty ? "settings.logs.empty" : "settings.logs.filtered-empty",
                systemImage: "list.bullet.rectangle"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(displayedEntries) { entry in
                            RuntimeLogRow(entry: entry)
                                .id(entry.id)
                            Divider()
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .onAppear {
                    scrollToTop(proxy: proxy)
                }
                .onChange(of: displayedEntries.first?.id) { _, _ in
                    scrollToTop(proxy: proxy)
                }
            }
        }
    }

    private var displayedEntries: [RuntimeLogEntry] {
        model.entries.reversed().filter { entry in
            levelFilter.includes(entry.level) && sourceFilter.includes(entry.source)
        }
    }

    private func scrollToTop(proxy: ScrollViewProxy) {
        guard let id = displayedEntries.first?.id else { return }
        proxy.scrollTo(id, anchor: .top)
    }
}

private struct RuntimeLogRow: View {
    let entry: RuntimeLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(levelTitle, systemImage: levelSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(levelColor)

                Text(entry.message)
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.timestamp, format: .dateTime.month().day().hour().minute().second())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            HStack(spacing: 7) {
                Text(sourceTitle)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())

                Text(categoryTitle)

                Text(entry.event.rawValue)
                    .fontDesign(.monospaced)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !entry.fields.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(entry.fields.enumerated()), id: \.offset) { _, field in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(fieldTitle(field.name))
                                .foregroundStyle(.secondary)
                                .frame(width: 46, alignment: .trailing)
                            Text(field.value)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .font(.caption)
                .padding(8)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 10)
    }

    private var sourceTitle: LocalizedStringKey {
        switch entry.source {
        case .application: "settings.logs.source.application"
        case .finderExtension: "settings.logs.source.finder"
        }
    }

    private var categoryTitle: LocalizedStringKey {
        switch entry.category {
        case .lifecycle: "settings.logs.category.lifecycle"
        case .templates: "settings.logs.category.templates"
        case .authorization: "settings.logs.category.authorization"
        case .finderMenu: "settings.logs.category.finder-menu"
        case .fileCreation: "settings.logs.category.file-creation"
        }
    }

    private var levelTitle: LocalizedStringKey {
        switch entry.level {
        case .debug: "settings.logs.level.debug"
        case .info: "settings.logs.level.info"
        case .notice: "settings.logs.level.notice"
        case .warning: "settings.logs.level.warning"
        case .error: "settings.logs.level.error"
        }
    }

    private var levelSymbol: String {
        switch entry.level {
        case .debug: "ladybug"
        case .info: "info.circle.fill"
        case .notice: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var levelColor: Color {
        switch entry.level {
        case .debug: .secondary
        case .info: .blue
        case .notice: .green
        case .warning: .orange
        case .error: .red
        }
    }

    private func fieldTitle(_ name: RuntimeLogFieldName) -> LocalizedStringKey {
        switch name {
        case .count: "settings.logs.field.count"
        case .path: "settings.logs.field.path"
        case .template: "settings.logs.field.template"
        case .identifier: "settings.logs.field.identifier"
        case .status: "settings.logs.field.status"
        case .reason: "settings.logs.field.reason"
        }
    }
}

private enum RuntimeLogLevelFilter: CaseIterable, Identifiable {
    case all
    case errors

    var id: Self {
        self
    }

    var title: LocalizedStringKey {
        switch self {
        case .all: "settings.logs.filter.all"
        case .errors: "settings.logs.filter.errors"
        }
    }

    func includes(_ level: RuntimeLogLevel) -> Bool {
        switch self {
        case .all: true
        case .errors: level == .error
        }
    }
}

private enum RuntimeLogSourceFilter: CaseIterable, Identifiable {
    case all
    case application
    case finder

    var id: Self {
        self
    }

    var title: LocalizedStringKey {
        switch self {
        case .all: "settings.logs.source.all"
        case .application: "settings.logs.source.application"
        case .finder: "settings.logs.source.finder"
        }
    }

    func includes(_ source: RuntimeLogSource) -> Bool {
        switch self {
        case .all: true
        case .application: source == .application
        case .finder: source == .finderExtension
        }
    }
}
