import SwiftUI

struct HeroRingsLegendSheet: View {
    let summary: DashboardSummary
    /// `period.type` из дашборда: today / custom / month_to_date / calendar_month.
    var periodType: String = ""
    var taxAmount: Double = 0
    var bankAccounts: [DashboardBankAccount]?
    var showBalance: Bool = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var bankBalance: Double? {
        guard showBalance else { return nil }
        return summary.resolvedBankBalanceTotal(accounts: bankAccounts)
    }

    private var ringsFooterText: String {
        if periodType == "today" || periodType == "custom" {
            return "Кольца: полный круг — средний дневной ориентир за текущий месяц до выбранного дня по поступлениям, продажам, расходу и налогу; для остатка — баланс на конец предыдущего периода. Заполнение — факт выбранного периода к этой цели."
        }
        return "Кольца: полный круг — факт предыдущего полного календарного месяца по каждому показателю; для остатка — баланс на конец предыдущего периода. Заполнение — за текущий выбранный период относительно этой цели."
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    legendRow(
                        color: DashboardRingPalette.revenue,
                        title: "Доходы",
                        value: DashboardMoney.formatTenge(summary.revenue),
                        subtitle: "Продажи за период"
                    )
                    if showBalance {
                        legendRow(
                            color: DashboardRingPalette.balance,
                            title: "Остаток",
                            value: DashboardMoney.formatOptionalTenge(bankBalance ?? summary.profit),
                            subtitle: bankBalance != nil
                                ? "Сумма остатков по банковским счетам"
                                : "Поступления минус расходы за период"
                        )
                    }
                    legendRow(
                        color: DashboardRingPalette.expense,
                        title: "Расходы",
                        value: DashboardMoney.formatTenge(summary.totalExpense),
                        subtitle: "Расходы за период"
                    )
                    legendRow(
                        color: DashboardRingPalette.receipts,
                        title: "Поступления",
                        value: DashboardMoney.formatTenge(summary.totalIncome),
                        subtitle: "Все поступления за период"
                    )
                    legendRow(
                        color: DashboardRingPalette.tax(colorScheme),
                        title: "Налоги",
                        value: DashboardMoney.formatTenge(max(taxAmount, 0)),
                        subtitle: summary.resolvedPotentialTaxHint
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

/// Справка у «Денежный остаток»: плановые платежи и согласованные заявки к оплате.
struct CashBalanceHintSheet: View {
    let summary: DashboardSummary
    let commitments: DashboardCashCommitments
    let bankAccounts: [DashboardBankAccount]?
    @Environment(\.dismiss) private var dismiss

    private var planned: Double { commitments.plannedWaitingTotal }
    private var approved: Double { commitments.approvedUnpaidTotal }
    private var totalCommitments: Double { commitments.total }
    private var bankBalance: Double? {
        summary.resolvedBankBalanceTotal(accounts: bankAccounts)
    }

    private var surplusAfterCommitments: Double {
        (bankBalance ?? 0) - totalCommitments
    }

    private var cashGapRisk: Bool {
        guard let balance = bankBalance else { return false }
        return totalCommitments > 1e-6 && balance + 1e-6 < totalCommitments
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        bulletRow(
                            "Плановые расходы до конца месяца. Все предстоящие платежи, в том числе просроченные: \(DashboardMoney.formatTenge(planned))."
                        )
                        bulletRow(
                            "Согласованные расходы в чате, ожидающие оплаты: \(DashboardMoney.formatTenge(approved))."
                        )
                        bulletRow(
                            "Всего к оплате по этим позициям: \(DashboardMoney.formatTenge(totalCommitments))."
                        )
                        bulletRow(
                            "Денежный остаток на главной — сумма остатков по банковским счетам на выбранную дату: \(DashboardMoney.formatOptionalTenge(bankBalance))."
                        )
                        if summary.resolvedBankBalanceIsStale(accounts: bankAccounts) {
                            bulletRow(
                                "Часть или все выписки старше 14 дней — сумма показана как ориентир и может отличаться от фактического баланса."
                            )
                            .foregroundStyle(.orange)
                        }
                        bulletRow(
                            "Если вычесть обязательства из этого остатка, получится ориентир: \(DashboardMoney.formatTenge(surplusAfterCommitments))."
                        )
                        if cashGapRisk {
                            bulletRow(
                                "Внимание: обязательств больше, чем известный остаток на счетах — возможен кассовый разрыв. Проверьте график платежей и остатки на счетах."
                            )
                            .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Обязательства к оплате")
                } footer: {
                    Text(
                        "Цифры по плановым платежам берутся из раздела планирования (статус «ожидает оплаты», срок до конца текущего месяца + просрочённые). По чату учитываются только сообщения со статусом «согласовано», по которым ещё не создана операция. Это ориентир, а не банковский остаток."
                    )
                }
            }
            .navigationTitle("Денежный остаток")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Форма внесения/обновления остатка наличных в кассе (точке).
struct CashBalanceEntrySheet: View {
    let register: CashRegister
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var amountDigits: String
    @State private var date: Date
    @State private var isSaving = false
    @State private var errorText: String?

    init(register: CashRegister, onSaved: @escaping () -> Void) {
        self.register = register
        self.onSaved = onSaved
        if let bal = register.balance {
            _amountDigits = State(initialValue: String(Int(bal.rounded())))
        } else {
            _amountDigits = State(initialValue: "")
        }
        let initialDate: Date = {
            if let iso = register.balanceDate {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                if let d = f.date(from: String(iso.prefix(10))) { return d }
            }
            return Date()
        }()
        _date = State(initialValue: initialDate)
    }

    private var amountValue: Int? {
        let cleaned = amountDigits.filter(\.isNumber)
        return cleaned.isEmpty ? nil : Int(cleaned)
    }

    private var formattedAmount: String {
        guard let v = amountValue else { return "" }
        return DashboardMoney.formatTenge(Double(v))
    }

    private var canSave: Bool {
        amountValue != nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Касса", value: register.label)
                    if let company = register.companyName, !company.isEmpty {
                        LabeledContent("Филиал", value: company)
                    }
                } footer: {
                    Text(register.pointId == nil
                         ? "Общая касса — наличные без привязки к точке."
                         : "Остаток наличных в этой точке на выбранную дату.")
                }

                Section("Остаток") {
                    HStack {
                        TextField("0", text: $amountDigits)
                            .keyboardType(.numberPad)
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .onChange(of: amountDigits) { _, newValue in
                                let filtered = newValue.filter(\.isNumber)
                                if filtered != newValue { amountDigits = filtered }
                            }
                        Spacer()
                        Text("₸")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if !formattedAmount.isEmpty {
                        Text(formattedAmount)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Дата") {
                    DatePicker(
                        "Дата остатка",
                        selection: $date,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                }

                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(register.hasBalance ? "Обновить остаток" : "Внести остаток")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Сохранить")
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    @MainActor
    private func save() async {
        guard let amount = amountValue else { return }
        isSaving = true
        errorText = nil
        defer { isSaving = false }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let dateStr = f.string(from: date)

        do {
            try await APIService.shared.saveCashBalance(
                pointId: register.pointId,
                amount: amount,
                date: dateStr
            )
            onSaved()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
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
                            .foregroundStyle(up ? DashboardRingPalette.revenue : DashboardRingPalette.expense)
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

// MARK: - Согласования

struct HomeApprovalsSheet: View {
    let stats: DashboardApprovalStats
    let periodLabel: String
    var onOpenChat: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var approvalSheetContext: ApprovalSheetContext?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Запросов", value: "\(stats.total)")
                    LabeledContent("Согласовано", value: "\(stats.approved)")
                    if stats.rejected > 0 {
                        LabeledContent("Отклонено", value: "\(stats.rejected)")
                    }
                    if stats.pendingInPeriod > 0 {
                        LabeledContent("Ожидает в периоде", value: "\(stats.pendingInPeriod)")
                    }
                } header: {
                    Text(periodLabel)
                }

                if !stats.pendingActionItems.isEmpty {
                    Section {
                        ForEach(stats.pendingActionItems) { item in
                            approvalRow(item)
                        }
                    } header: {
                        Label("Требуется ваш ответ", systemImage: "exclamationmark.circle.fill")
                    } footer: {
                        if stats.pendingActionItems.contains(where: \.outsidePeriod) {
                            Text("В том числе запросы вне выбранного периода — их нужно обработать в любом случае.")
                                .font(.caption)
                        }
                    }
                }

                if !stats.periodItems.isEmpty {
                    Section("За период") {
                        ForEach(stats.periodItems) { item in
                            approvalRow(item)
                        }
                    }
                } else if stats.pendingActionItems.isEmpty {
                    Section {
                        Text("За выбранный период запросов на согласование не было.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Согласования")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .sheet(item: $approvalSheetContext) { context in
                ApprovalActionSheet(context: context) { convId in
                    if convId > 0 {
                        onOpenChat(convId)
                    }
                }
            }
        }
    }

    private func approvalRow(_ item: DashboardApprovalItem) -> some View {
        Button {
            approvalSheetContext = ApprovalSheetContext(item: item)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    statusBadge(item)
                }
                if !item.formattedAmount.isEmpty {
                    Text(item.formattedAmount)
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                }
                if let desc = item.payload.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    if !item.senderName.isEmpty {
                        Text(item.senderName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(shortDate(item.createdAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func statusBadge(_ item: DashboardApprovalItem) -> some View {
        let (text, color): (String, Color) = {
            if item.needsAction {
                return ("Ожидает ответа", .orange)
            }
            switch item.approvalStatus {
            case .approved: return ("Согласовано", DashboardPalette.income)
            case .rejected: return ("Отклонено", DashboardPalette.expense)
            case .pending: return ("Ожидает", .orange)
            case .none: return ("—", .secondary)
            }
        }()
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func shortDate(_ iso: String) -> String {
        let trimmed = String(iso.prefix(10))
        return DashboardMoney.longDateLabel(trimmed)
    }
}
