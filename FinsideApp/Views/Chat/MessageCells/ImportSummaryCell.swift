import SwiftUI

struct ImportSummaryCell: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
                Text("Импорт выписки")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let bank = message.payload.bank {
                    Text(bank.capitalized)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1), in: Capsule())
                        .foregroundStyle(.blue)
                }
            }

            Text(message.text)
                .font(.body)

            HStack(spacing: 16) {
                if let income = message.payload.incomeCount {
                    metricBadge(icon: "arrow.down.circle", label: "Доходы", count: income, color: .green)
                }
                if let expense = message.payload.expenseCount {
                    metricBadge(icon: "arrow.up.circle", label: "Расходы", count: expense, color: .red)
                }
                if let transfer = message.payload.transferCount {
                    metricBadge(icon: "arrow.left.arrow.right.circle", label: "Переводы", count: transfer, color: .secondary)
                }
            }

            if let iban = message.payload.iban, !iban.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "creditcard")
                        .font(.caption2)
                    Text(iban)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            Button {
                // Navigate to categorization flow
            } label: {
                Label("Разметить категории", systemImage: "tag")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }

            Text(message.formattedTime)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .liquidGlassCard(cornerRadius: 16)
    }

    private func metricBadge(icon: String, label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text("\(count)")
                .font(.headline.weight(.bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
