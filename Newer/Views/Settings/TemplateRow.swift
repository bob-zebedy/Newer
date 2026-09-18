import SwiftUI

struct TemplateRow<DragHandle: View>: View {
    let item: TemplateItem
    let onUpdate: (TemplateItem) -> Void
    @ViewBuilder let dragHandle: DragHandle

    var body: some View {
        HStack(spacing: 12) {
            dragHandle

            TemplateSelectionCheckbox(
                state: item.isEnabled ? .enabled : .disabled
            ) {
                var updated = item
                updated.isEnabled.toggle()
                onUpdate(updated)
            }
            .frame(width: 20, height: 20)

            Image(systemName: "doc")
                .font(.system(size: 17))
                .foregroundStyle(item.isEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                TextField("settings.templates.display-name", text: Binding(
                    get: { item.displayName },
                    set: { value in
                        var updated = item
                        updated.displayName = value
                        onUpdate(updated)
                    }
                ))
                .textFieldStyle(.plain)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .onSubmit(commitName)
                Text(item.relativePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)
        }
        .opacity(item.isEnabled ? 1 : 0.62)
    }

    private func commitName() {
        var updated = item
        updated.displayName = updated.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if updated.displayName.isEmpty {
            updated.displayName = TemplateItem.defaultDisplayName(for: updated.relativePath)
        }
        onUpdate(updated)
    }
}
