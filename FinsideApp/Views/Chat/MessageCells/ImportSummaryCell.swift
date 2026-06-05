import SwiftUI

struct ImportSummaryCell: View {
    let message: ChatMessage
    /// Меняется после закрытия экрана разметки — перезапрашиваем число неразмеченных операций.
    var refreshToken: Int = 0
    var onMarkCategories: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @State private var uncategorizedCount: Int?

    /// Показываем метрики (доходы/расходы/переводы) только если из выписки реально добавились операции.
    private var hasNewOperationsToShow: Bool {
        let p = message.payload
        if p.emptyImport == true { return false }
        let total = (p.incomeCount ?? 0) + (p.expenseCount ?? 0) + (p.transferCount ?? 0)
        return total > 0
    }

    /// Кнопку показываем, пока в выписке есть неразмеченные доходы/расходы.
    private var showMarkCategoriesButton: Bool {
        guard hasNewOperationsToShow else { return false }
        guard let uncategorizedCount else { return true }
        return uncategorizedCount > 0
    }

    private var uncategorizedFetchKey: String {
        "\(message.id)-\(refreshToken)-\(message.payload.uploadId ?? 0)-\(message.payload.iban ?? "")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(0.14))
                        .frame(width: 30, height: 30)
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.blue)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Импорт выписки")
                        .font(.caption.weight(.semibold))
                    if let bank = message.payload.bank, !bank.isEmpty {
                        Text(bank.capitalized)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                Text(message.formattedTime)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }

            if hasNewOperationsToShow {
                compactMetricsRow
            } else if !message.text.isEmpty {
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let iban = message.payload.iban, !iban.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "creditcard")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Text(iban)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            if showMarkCategoriesButton {
                Button {
                    onMarkCategories?()
                } label: {
                    Label("Разметить категории", systemImage: "tag.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .liquidGlassCard(cornerRadius: 14)
        .task(id: uncategorizedFetchKey) {
            await refreshUncategorizedCount()
        }
    }

    private func refreshUncategorizedCount() async {
        guard hasNewOperationsToShow else {
            uncategorizedCount = 0
            return
        }

        do {
            let page = try await APIService.shared.uncategorizedTransactions(
                uploadId: message.payload.uploadId,
                iban: message.payload.iban,
                offset: 0,
                limit: 1
            )
            uncategorizedCount = page.count
        } catch {
            uncategorizedCount = nil
        }
    }

    @ViewBuilder
    private var compactMetricsRow: some View {
        HStack(spacing: 6) {
            if let income = message.payload.incomeCount {
                compactMetricChip(
                    icon: "arrow.down.circle.fill",
                    value: income,
                    label: "доход",
                    tint: DashboardPalette.income
                )
            }
            if let expense = message.payload.expenseCount {
                compactMetricChip(
                    icon: "arrow.up.circle.fill",
                    value: expense,
                    label: "расход",
                    tint: DashboardPalette.expense
                )
            }
            if let transfer = message.payload.transferCount {
                compactMetricChip(
                    icon: "arrow.left.arrow.right.circle.fill",
                    value: transfer,
                    label: "перевод",
                    tint: DashboardPalette.transfer
                )
            }
        }
    }

    private func compactMetricChip(icon: String, value: Int, label: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
            Text("\(value)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(metricTileFill)
        }
    }

    private var metricTileFill: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemFill)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.secondary.opacity(0.1)
        #endif
    }
}
