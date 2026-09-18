import SwiftUI

struct TemplateSettingsView: View {
    @ObservedObject var model: TemplateSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("settings.templates.title")
                    .font(.callout.weight(.medium))

                Spacer()

                Text(templateCountTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()

                Button {
                    model.openTemplateDirectory()
                } label: {
                    Label("settings.templates.open-directory", systemImage: "folder")
                }
                .fixedSize()
            }

            TemplateListView(
                items: model.items,
                onUpdate: model.update,
                onSetEnabled: model.setEnabled(_:for:),
                onMove: model.moveTemplateEntries(within:fromOffsets:toOffset:)
            )
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var templateCountTitle: String {
        let enabledCount = model.items.filter(\.isEnabled).count
        return String.localizedStringWithFormat(
            String(localized: "settings.templates.enabled-count"),
            Int64(enabledCount),
            Int64(model.items.count)
        )
    }
}
