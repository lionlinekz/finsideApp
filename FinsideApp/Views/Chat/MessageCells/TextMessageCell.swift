import SwiftUI

struct TextMessageCell: View {
    let message: ChatMessage
    @Environment(\.colorScheme) private var colorScheme

    private var isOwnMessage: Bool {
        message.senderId != nil && !message.isSystem
    }

    var body: some View {
        Group {
            if message.isSystem {
                systemPill
            } else {
                userBubbleRow
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - User bubbles (Messages-like)

    private var userBubbleRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isOwnMessage { Spacer(minLength: 56) }

            VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 5) {
                if !message.senderName.isEmpty {
                    Text(message.senderName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(message.text)
                    .font(.body)
                    .foregroundStyle(isOwnMessage ? Color.white : Color.primary)
                    .multilineTextAlignment(isOwnMessage ? .trailing : .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(isOwnMessage ? outgoingFill : incomingFill)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                isOwnMessage
                                    ? Color.white.opacity(colorScheme == .dark ? 0.12 : 0.18)
                                    : Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06),
                                lineWidth: 0.5
                            )
                    }
                    .shadow(color: isOwnMessage ? .clear : bubbleShadow, radius: 10, y: 4)

                Text(message.formattedTime)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }

            if !isOwnMessage { Spacer(minLength: 56) }
        }
    }

    private var outgoingFill: Color {
        Color.accentColor
    }

    private var incomingFill: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemFill)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.secondary.opacity(0.14)
        #endif
    }

    private var bubbleShadow: Color {
        colorScheme == .dark ? .black.opacity(0.45) : .black.opacity(0.07)
    }

    // MARK: - System (centered)

    private var systemPill: some View {
        Text(message.text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
    }
}
