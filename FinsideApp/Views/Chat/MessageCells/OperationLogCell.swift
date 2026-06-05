import SwiftUI

struct OperationLogCell: View {
    let message: ChatMessage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            Spacer(minLength: 28)
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)

                Text(message.text)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("·")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.quaternary)

                Text(message.formattedTime)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(ribbonFill)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 0.5)
            }
            Spacer(minLength: 28)
        }
    }

    private var ribbonFill: Color {
        #if os(iOS)
        Color(uiColor: .tertiarySystemFill)
        #elseif os(macOS)
        Color(nsColor: .quaternarySystemFill)
        #else
        Color.secondary.opacity(0.12)
        #endif
    }
}
