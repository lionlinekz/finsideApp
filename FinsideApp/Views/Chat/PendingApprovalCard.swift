import SwiftUI

struct PendingApprovalCard: View {
    let item: PendingApprovalItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.orange)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(titleText)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }

                    if !descriptionText.isEmpty {
                        Text(descriptionText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var titleText: String {
        if !item.formattedAmount.isEmpty { return item.formattedAmount }
        return "Согласование"
    }

    private var descriptionText: String {
        if let desc = item.payload.description, !desc.isEmpty {
            return desc
        }
        return ""
    }

    private var subtitleText: String {
        if !item.senderName.isEmpty { return item.senderName }
        if !item.conversationTitle.isEmpty { return item.conversationTitle }
        return "Запрос на согласование"
    }
}
