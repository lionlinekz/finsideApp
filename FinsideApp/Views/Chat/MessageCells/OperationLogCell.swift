import SwiftUI

struct OperationLogCell: View {
    let message: ChatMessage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(message.text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(message.formattedTime)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}
