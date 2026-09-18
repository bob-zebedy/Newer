import SwiftUI

struct SettingsSectionTitle: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.headline)
    }
}

struct SettingsSurfaceCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
            }
    }
}

struct SettingsStatusBadge: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.11), in: Capsule())
    }
}
