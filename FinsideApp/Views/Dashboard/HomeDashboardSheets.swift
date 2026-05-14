import SwiftUI

struct HeroRingsLegendSheet: View {
    let summary: DashboardSummary
    /// `period.type` из дашборда: today / custom / month_to_date / calendar_month.
    var periodType: String = ""
    @Environment(\.dismiss) private var dismiss

    private var ringsFooterText: String {
        if periodType == "today" || periodType == "custom" {
            return "Кольца: полный круг — средний дневной ориентир за текущий месяц до выбранного дня (сумма с 1-го числа, делённая на число дня) отдельно по поступлениям, расходу и денежному остатку. Заполнение — факт выбранного периода к этой цели."
        }
        return "Кольца: полный круг — факт предыдущего полного календарного месяца по поступлениям, расходу и денежному остатку. Заполнение — за текущий выбранный период относительно этой цели."
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    legendRow(
                        color: DashboardPalette.receipts,
                        title: "Поступления",
                        value: DashboardMoney.formatTenge(summary.totalIncome),
                        subtitle: "Все поступления за период"
                    )
                    legendRow(
                        color: DashboardPalette.expense,
                        title: "Расход",
                        value: DashboardMoney.formatTenge(summary.totalExpense),
                        subtitle: "Расходы за период"
                    )
                    legendRow(
                        color: DashboardPalette.income,
                        title: "Денежный остаток",
                        value: DashboardMoney.formatTenge(summary.profit),
                        subtitle: "Поступления минус расходы за период"
                    )
                } header: {
                    Text("Кольца")
                } footer: {
                    Text(ringsFooterText)
                }
            }
            .navigationTitle("Показатели")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private func legendRow(color: Color, title: String, value: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(value).font(.subheadline.monospacedDigit().weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MetricComparisonSheet: View {
    let title: String
    let tint: Color
    let current: Double
    let previous: Double
    @Environment(\.dismiss) private var dismiss

    private var deltaPct: Double? {
        guard previous != 0 else { return current != 0 ? 100 : nil }
        return ((current - previous) / abs(previous)) * 100
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Сейчас", value: DashboardMoney.formatTenge(current))
                    LabeledContent("Прошлый период", value: DashboardMoney.formatTenge(previous))
                    if let d = deltaPct {
                        let up = d >= 0
                        LabeledContent("Изменение") {
                            HStack(spacing: 4) {
                                Image(systemName: up ? "arrow.up" : "arrow.down")
                                Text(String(format: "%.0f%%", abs(d)))
                            }
                            .foregroundStyle(up ? Color(red: 0.13, green: 0.78, blue: 0.56) : Color(red: 0.94, green: 0.30, blue: 0.30))
                            .font(.body.weight(.semibold).monospacedDigit())
                        }
                    }
                } footer: {
                    Text("Сравнение с предыдущим интервалом той же длины (как на главной).")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .tint(tint)
    }
}

struct TaxEstimateSheet: View {
    let summary: DashboardSummary
    var primaryBranch: BranchCompany? = nil
    @Environment(\.dismiss) private var dismiss

    private var taxLine: (amount: Double, hint: String) {
        DashboardDisplayTax.compute(summary: summary, primaryBranch: primaryBranch)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let title = summary.taxRegimeTitleRu, !title.isEmpty {
                        LabeledContent("Режим", value: title)
                    } else {
                        LabeledContent("Режим", value: "—")
                    }
                    if let src = summary.taxRegimeSourceLabelRu, !src.isEmpty {
                        LabeledContent("Источник", value: src)
                    }
                    if let code = summary.taxRegimeCode, !code.isEmpty {
                        LabeledContent("Код") {
                            Text(code)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text("Режим для оценки")
                } footer: {
                    Text("Оценка считается по первой компании из филиалов и показателям дашборда за выбранный период. Сменить режим: «Настройки» → «Компания» или «Филиалы».")
                        .font(.caption)
                }
                Section {
                    LabeledContent("Оценка", value: DashboardMoney.formatTenge(taxLine.amount))
                } footer: {
                    Text(taxLine.hint)
                }
                Section {
                    Text("Это упрощённая оценка для ориентира, а не налоговая или бухгалтерская консультация. Для расчётов обращайтесь к специалисту.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Налог (оценка)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

struct ChartDaySheet: View {
    let point: ChartPoint
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Дата", value: DashboardMoney.longDateLabel(point.date))
                    LabeledContent("Доход", value: DashboardMoney.formatTenge(point.income))
                    LabeledContent("Расход", value: DashboardMoney.formatTenge(point.expense))
                }
            }
            .navigationTitle("День")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
