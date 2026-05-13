import SwiftUI

struct PendingApprovalCard: View {
    let item: PendingApprovalItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Согласование")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if !item.formattedAmount.isEmpty {
                    Text(item.formattedAmount)
                        .font(.title3.weight(.bold))
                }

                if let desc = item.payload.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack {
                    Image(systemName: "person.circle")
                        .font(.caption)
                    Text(item.senderName.isEmpty ? "Менеджер" : item.senderName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(width: 180, alignment: .leading)
            .liquidGlassCard(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }
}
