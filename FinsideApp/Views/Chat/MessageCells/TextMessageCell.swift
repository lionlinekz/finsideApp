import SwiftUI

struct TextMessageCell: View {
    let message: ChatMessage

    private var isOwnMessage: Bool {
        message.senderId != nil && !message.isSystem
    }

    var body: some View {
        HStack {
            if isOwnMessage { Spacer(minLength: 60) }

            VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 4) {
                if !message.isSystem && !message.senderName.isEmpty {
                    Text(message.senderName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(message.text)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        isOwnMessage
                            ? Color.accentColor.opacity(0.15)
                            : Color.secondary.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 18)
                    )

                Text(message.formattedTime)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !isOwnMessage { Spacer(minLength: 60) }
        }
    }
}
