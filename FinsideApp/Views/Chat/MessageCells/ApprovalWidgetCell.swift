import SwiftUI

struct ApprovalWidgetCell: View {
    let message: ChatMessage
    @Environment(ChatService.self) private var chatService

    private var isPending: Bool {
        message.approvalStatus == .pending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                Text("Запрос согласования")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                statusBadge
            }

            if let amount = message.payload.amount,
               let money = MoneyAmount(fromString: amount) {
                Text(money.formattedWithCurrency)
                    .font(.title2.weight(.bold))
            }

            if let desc = message.payload.description, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !message.senderName.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "person.circle")
                        .font(.caption)
                    Text(message.senderName)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            if isPending {
                HStack(spacing: 12) {
                    Button {
                        Task { await chatService.approve(messageId: message.id) }
                    } label: {
                        Label("Согласовать", systemImage: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                    }

                    Button {
                        Task { await chatService.reject(messageId: message.id) }
                    } label: {
                        Label("Отклонить", systemImage: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.red)
                    }
                }
            }

            Text(message.formattedTime)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .liquidGlassCard(cornerRadius: 16)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let status = message.approvalStatus {
            Text(status.localized)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.15), in: Capsule())
                .foregroundStyle(statusColor)
        }
    }

    private var statusColor: Color {
        switch message.approvalStatus {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .red
        case nil: return .secondary
        }
    }
}
