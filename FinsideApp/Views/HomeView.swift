import SwiftUI

enum DatePeriod: String, CaseIterable, Identifiable {
    case monthToDate = "С начала месяца"
    case today = "Сегодня"
    case selectMonth = "Выбрать месяц"
    case custom = "Выбрать дату"
    var id: String { rawValue }
    var apiValue: String {
        switch self {
        case .monthToDate: return "month_to_date"
        case .today: return "today"
        case .selectMonth: return "calendar_month"
        case .custom: return "custom"
        }
    }
}

/// «Май 2026» для ru_RU (именительный падеж, с заглавной буквы).
private func ruMonthYearLabel(for date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ru_RU")
    f.dateFormat = "LLLL yyyy"
    let s = f.string(from: date)
    guard let first = s.first else { return s }
    return String(first).uppercased(with: f.locale) + s.dropFirst()
}

private extension Color {
    static let fIncome = Color(red: 0.13, green: 0.78, blue: 0.56)
    static let fExpense = Color(red: 0.94, green: 0.30, blue: 0.30)
    static let fRevenue = Color(red: 0.10, green: 0.40, blue: 0.28)
    static let fTransfer = Color(red: 0.55, green: 0.55, blue: 0.58)
    static let fTaxEstimate = Color(red: 0.85, green: 0.55, blue: 0.20)
    static let fProfit = Color(red: 1.0, green: 0.80, blue: 0.0)
}

private func brandColor(for name: String) -> Color {
    switch name.lowercased() {
    case let s where s.contains("kaspi"):
        return Color(red: 0.95, green: 0.27, blue: 0.21)
    case let s where s.contains("halyk") || s.contains("халык"):
        return Color(red: 0.0, green: 0.65, blue: 0.31)
    case let s where s.contains("forte") || s.contains("форте"):
        return Color(red: 0.35, green: 0.17, blue: 0.53)
    case let s where s.contains("bcc") || s.contains("центркредит"):
        return Color(red: 0.0, green: 0.24, blue: 0.65)
    case let s where s.contains("jusan") || s.contains("жусан"):
        return Color(red: 0.96, green: 0.72, blue: 0.0)
    case let s where s.contains("eurasian") || s.contains("евразийский"):
        return Color(red: 0.85, green: 0.11, blue: 0.14)
    case let s where s.contains("altyn") || s.contains("алтын"):
        return Color(red: 0.80, green: 0.63, blue: 0.13)
    case let s where s.contains("otbasy") || s.contains("отбасы"):
        return Color(red: 0.0, green: 0.48, blue: 0.80)
    case let s where s.contains("freedom") || s.contains("фридом"):
        return Color(red: 0.0, green: 0.72, blue: 0.58)
    case let s where s.contains("bereke"):
        return Color(red: 0.0, green: 0.55, blue: 0.47)
    case let s where s.contains("наличн") || s.contains("cash"):
        return Color(red: 0.38, green: 0.55, blue: 0.42)
    case let s where s.contains("безнал") || s.contains("bank") || s.contains("перевод"):
        return Color(red: 0.15, green: 0.42, blue: 0.68)
    case let s where s.contains("карт") || s.contains("card"):
        return Color(red: 0.55, green: 0.38, blue: 0.68)
    default:
        return Color(red: 0.45, green: 0.48, blue: 0.52)
    }
}

/// Раскрытая детализация в блоке «Источники доходов» (банки / наличные личн.–бизнес).
private enum PaymentSourcesExpansion: Equatable {
    case none
    case bankBreakdown
    case cashSplit
}

private enum HomeDetailSheet: Identifiable {
    case heroLegend(DashboardSummary, String)
    case incomeDetail(DashboardSummary, PeriodComparison)
    case expenseDetail(DashboardSummary, PeriodComparison)
    case taxDetail(DashboardSummary, BranchCompany?)
    case chartDay(ChartPoint)

    var id: String {
        switch self {
        case .heroLegend: return "hero"
        case .incomeDetail: return "income"
        case .expenseDetail: return "expense"
        case .taxDetail: return "tax"
        case .chartDay(let p): return "chart-\(p.date)"
        }
    }
}

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(ChatService.self) private var chatService
    @State private var selectedPeriod: DatePeriod = .monthToDate
    @State private var customDate: Date = .now
    @State private var selectedMonth: Date = .now
    /// Месяц для режима «С начала месяца» (со свайпом).
    @State private var mtdAnchorMonth: Date = HomeView.startOfMonth(Date())
    /// День для режима «Сегодня» (со свайпом по дням).
    @State private var todayViewDay: Date = HomeView.startOfDay(Date())
    /// Локальное состояние листа «Выбрать месяц» (только месяц и год, без дня).
    @State private var pickMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var pickYear: Int = Calendar.current.component(.year, from: Date())
    @State private var showDatePicker = false
    @State private var showMonthPicker = false
    @State private var dashboard: DashboardResponse?
    @State private var primaryBranch: BranchCompany?
    /// Старт с true, чтобы не мигать пустым «Нет данных» до первого кадра загрузки.
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var appeared = false
    @State private var paymentSourcesExpansion: PaymentSourcesExpansion = .none
    @State private var detailSheet: HomeDetailSheet?
    @State private var ledgerPath = NavigationPath()
    /// Горизонтальный свайп для смены периода: −1…1 (блик + «резина» контента).
    @State private var periodSwipeSheenPhase: CGFloat = 0
    /// Смещение ленты дашборда за пальцем (pt), с упругим сбросом.
    @State private var periodSwipeNudgeX: CGFloat = 0
    /// Раскрытый блок «Банковские счета» под «Денежный остаток» (тап по остатку).
    @State private var expandedBankAccountsUnderOstatok = false

    /// Мягкое ограничение как у растягивания у края экрана.
    private static func swipeRubberNudge(dx: CGFloat) -> CGFloat {
        let sign: CGFloat = dx >= 0 ? 1 : -1
        let a = min(abs(dx), 320)
        let t = Double(a / 210)
        let eased = 1 - exp(-t * 2.4)
        return sign * CGFloat(eased) * 11
    }

    private static let swipeResetAnimation = Animation.spring(response: 0.42, dampingFraction: 0.84)
    /// Совпадает с `BANK_BALANCE_STALE_DAYS` в API дашборда.
    private static let bankBalanceStaleDays = 14

    var body: some View {
        NavigationStack(path: $ledgerPath) {
            ScrollView {
                Group {
                    if let err = errorMessage, !isLoading {
                        errorView(err)
                    } else if isLoading, dashboard == nil {
                        loadingPlaceholder
                    } else if let dashboard {
                        contentInner(dashboard)
                            .offset(x: periodSwipeNudgeX)
                            .overlay {
                                PeriodSwipeGlow(progress: periodSwipeSheenPhase)
                            }
                    } else {
                        emptyView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            // Один жест на ScrollView: два simultaneousGesture (здесь и на внутреннем контенте)
            // давали двойной onEnded → перескок на 2 месяца/дня за один свайп.
            .simultaneousGesture(periodSwipeGesture)
            .background(Color(.systemBackground))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { periodMenu }
                ToolbarItem(placement: .topBarTrailing) { AvatarMenuButton() }
            }
            .refreshable { await loadDataAsync() }
            .onReceive(NotificationCenter.default.publisher(for: .finsideLedgerDidChange)) { _ in
                Task { await loadDataAsync() }
            }
            .sheet(isPresented: $showDatePicker) { datePickerSheet }
            .sheet(isPresented: $showMonthPicker) { monthPickerSheet }
            .onAppear { if !appeared { appeared = true; loadData() } }
            .onChange(of: selectedPeriod) { _, _ in
                expandedBankAccountsUnderOstatok = false
                resetAnchorsForNewPeriod()
                loadData()
            }
            .navigationDestination(for: HomeLedgerRoute.self) { route in
                LedgerListView(route: route, period: selectedPeriod.apiValue, date: ledgerDateParam())
            }
            .sheet(item: $detailSheet) { sheet in
                switch sheet {
                case .heroLegend(let s, let periodType):
                    HeroRingsLegendSheet(summary: s, primaryBranch: primaryBranch, periodType: periodType)
                        .presentationDetents([.medium, .large])
                case .incomeDetail(let s, let c):
                    MetricComparisonSheet(
                        title: "Доход",
                        tint: Color.fIncome,
                        current: s.totalIncome,
                        previous: c.prevIncome
                    )
                    .presentationDetents([.medium])
                case .expenseDetail(let s, let c):
                    MetricComparisonSheet(
                        title: "Расход",
                        tint: Color.fExpense,
                        current: s.totalExpense,
                        previous: c.prevExpense
                    )
                    .presentationDetents([.medium])
                case .taxDetail(let s, let b):
                    TaxEstimateSheet(summary: s, primaryBranch: b)
                        .presentationDetents([.medium, .large])
                case .chartDay(let p):
                    ChartDaySheet(point: p)
                        .presentationDetents([.medium])
                }
            }
        }
    }

    private func ledgerDateParam() -> String? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        switch selectedPeriod {
        case .today:
            return f.string(from: todayViewDay)
        case .monthToDate:
            return monthFirstDayISO(from: mtdAnchorMonth)
        case .custom:
            return f.string(from: customDate)
        case .selectMonth:
            return monthFirstDayISO(from: selectedMonth)
        }
    }

    private func monthFirstDayISO(from date: Date) -> String {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month], from: date)
        let start = cal.date(from: c) ?? date
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: start)
    }

    private var periodSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                // Вертикальный скролл не дёргает ленту; горизонталь даёт связный блик + сдвиг.
                guard abs(dx) > 6 || abs(dx) >= abs(dy) * 0.7 else {
                    periodSwipeSheenPhase = 0
                    periodSwipeNudgeX = 0
                    return
                }
                periodSwipeNudgeX = Self.swipeRubberNudge(dx: dx)
                periodSwipeSheenPhase = min(1, max(-1, dx / 125))
            }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                withAnimation(Self.swipeResetAnimation) {
                    periodSwipeSheenPhase = 0
                    periodSwipeNudgeX = 0
                }
                guard abs(dx) > abs(dy) * 1.2, abs(dx) > 48 else { return }
                DashboardHaptics.lightImpact()
                if dx < 0 {
                    shiftFocusedPeriod(step: 1)
                } else {
                    shiftFocusedPeriod(step: -1)
                }
            }
    }

    private func shiftFocusedPeriod(step: Int) {
        let cal = Calendar.current
        switch selectedPeriod {
        case .today:
            guard let d = cal.date(byAdding: .day, value: step, to: todayViewDay) else { return }
            todayViewDay = Self.startOfDay(d)
        case .monthToDate:
            guard let d = cal.date(byAdding: .month, value: step, to: mtdAnchorMonth) else { return }
            mtdAnchorMonth = Self.startOfMonth(d)
        case .selectMonth:
            guard let d = cal.date(byAdding: .month, value: step, to: selectedMonth) else { return }
            selectedMonth = Self.startOfMonth(d)
        case .custom:
            guard let d = cal.date(byAdding: .day, value: step, to: customDate) else { return }
            customDate = Self.startOfDay(d)
        }
        loadData()
    }

    private func resetAnchorsForNewPeriod() {
        switch selectedPeriod {
        case .today:
            todayViewDay = Self.startOfDay(Date())
        case .monthToDate:
            mtdAnchorMonth = Self.startOfMonth(Date())
        case .selectMonth, .custom:
            break
        }
    }

    private static func startOfDay(_ d: Date) -> Date {
        Calendar.current.startOfDay(for: d)
    }

    private static func startOfMonth(_ d: Date) -> Date {
        let c = Calendar.current.dateComponents([.year, .month], from: d)
        return Calendar.current.date(from: c) ?? d
    }

    // MARK: - Content

    /// Контент дашборда без внешних отступов (их даёт родитель ScrollView для жеста).
    private func contentInner(_ d: DashboardResponse) -> some View {
        let tax = DashboardDisplayTax.compute(summary: d.summary, primaryBranch: primaryBranch)
        return VStack(spacing: 20) {
            heroSection(
                d.summary,
                comparison: d.comparison,
                taxDisplay: tax,
                ringTargets: d.ringTargets,
                periodType: d.period.type,
                bankAccounts: d.bankAccounts,
                showBankAccountsExpanded: $expandedBankAccountsUnderOstatok
            )

            if !d.managers.isEmpty {
                sectionBlock("Менеджеры") { managersSection(d.managers, revenue: d.summary.revenue) }
            }
            if !d.points.isEmpty {
                sectionBlock("Точки продаж") { pointsSection(d.points, revenue: d.summary.revenue) }
            }
            if !d.incomeByMethod.isEmpty || !d.incomeByBank.isEmpty {
                sectionBlock("Источники доходов") { paymentSourcesSection(d) }
            }
            let expenseAccountSplitTotal = (d.expenseFromIpAccounts ?? 0) + (d.expenseFromOwnAccounts ?? 0)
            if expenseAccountSplitTotal > 0 {
                sectionBlock("Оплаты расходов") { expenseAccountSourceSection(d) }
            }
            if !d.expensesByCategory.isEmpty {
                sectionBlock("Топ расходов") { expensesCategorySection(d.expensesByCategory, revenue: d.summary.revenue) }
            }
            if !d.chart.isEmpty {
                sectionBlock("Динамика") { chartSection(d.chart) }
            }

            if d.summary.totalIncome == 0, d.summary.totalExpense == 0, d.summary.revenue == 0 {
                Text("За выбранный период нет доходов и расходов в данных.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            Color.clear.frame(height: 32)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }


    private func heroSection(
        _ s: DashboardSummary,
        comparison prev: PeriodComparison,
        taxDisplay: (amount: Double, hint: String),
        ringTargets: RingTargets?,
        periodType: String,
        bankAccounts: [DashboardBankAccount]?,
        showBankAccountsExpanded: Binding<Bool>
    ) -> some View {
        let hasBankAccounts = !(bankAccounts ?? []).isEmpty
        return VStack(spacing: 16) {
            // Rings + блок с кольцами
            ZStack {
                Color(.secondarySystemGroupedBackground)

                HStack(spacing: 20) {
                    Button {
                        DashboardHaptics.lightImpact()
                        detailSheet = .heroLegend(s, periodType)
                    } label: {
                        ringsView(s, taxAmount: taxDisplay.amount, targets: ringTargets)
                            .frame(width: 120, height: 120)
                    }
                    .buttonStyle(.dashboardPressable)

                    VStack(alignment: .leading, spacing: 8) {
                        Group {
                            if hasBankAccounts {
                                Button {
                                    showBankAccountsExpanded.wrappedValue.toggle()
                                    DashboardHaptics.lightImpact()
                                } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Денежный остаток")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                            Text(fmt(s.profit))
                                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                                .foregroundStyle(s.profit >= 0 ? Color.fIncome : Color.fExpense)

                                            if let d = deltaPct(s.profit, prev.prevProfit) {
                                                deltaLabel(d)
                                            }
                                        }
                                        Spacer(minLength: 4)
                                        Image(systemName: showBankAccountsExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Показать или скрыть остатки по банковским счетам")
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Денежный остаток")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(fmt(s.profit))
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .foregroundStyle(s.profit >= 0 ? Color.fIncome : Color.fExpense)

                                    if let d = deltaPct(s.profit, prev.prevProfit) {
                                        deltaLabel(d)
                                    }
                                }
                            }
                        }

                        Divider().frame(width: 100)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Поступления")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(fmtShort(s.totalIncome))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                    }
                    Spacer()
                }
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if hasBankAccounts, showBankAccountsExpanded.wrappedValue, let banks = bankAccounts {
                bankAccountsSnapshotSection(banks)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Metric row
            HStack(alignment: .top, spacing: 10) {
                MetricRow(
                    label: "Доход",
                    value: s.revenue,
                    tint: .fIncome,
                    delta: deltaPct(s.revenue, prev.prevRevenue),
                    lightOnDark: true,
                    amountColor: .fIncome,
                    onTap: {
                        DashboardHaptics.lightImpact()
                        ledgerPath.append(HomeLedgerRoute.allIncome(title: "Доходы"))
                    }
                )
                MetricRow(
                    label: "Расход",
                    value: s.totalExpense,
                    tint: .fExpense,
                    delta: deltaPct(s.totalExpense, prev.prevExpense),
                    lightOnDark: true,
                    amountColor: .fExpense,
                    onTap: {
                        DashboardHaptics.lightImpact()
                        detailSheet = .expenseDetail(s, prev)
                    }
                )
                MetricRow(
                    label: "Налог",
                    value: taxDisplay.amount,
                    tint: .fTaxEstimate,
                    delta: nil,
                    subtitle: nil,
                    showApproximateBadge: false,
                    lightOnDark: true,
                    amountColor: .fTaxEstimate,
                    onTap: {
                        DashboardHaptics.lightImpact()
                        detailSheet = .taxDetail(s, primaryBranch)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.22), value: showBankAccountsExpanded.wrappedValue)
    }

    private func ringsView(_ s: DashboardSummary, taxAmount: Double, targets: RingTargets?) -> some View {
        let inc = s.totalIncome
        let exp = s.totalExpense
        let tax = max(0, taxAmount)
        let fallbackNorm = max(inc, exp, tax, 1)

        let incomeRatio = ringFillRatio(actual: inc, target: targets?.income, fallbackDenominator: fallbackNorm)
        let expenseRatio = ringFillRatio(actual: exp, target: targets?.expense, fallbackDenominator: fallbackNorm)
        let taxRatio = ringFillRatio(actual: tax, target: targets?.tax, fallbackDenominator: fallbackNorm)

        return ZStack {
            ring(ratio: incomeRatio, color: .fIncome, width: 10, size: 110)
            ring(ratio: expenseRatio, color: .fExpense, width: 10, size: 84)
            ring(ratio: taxRatio, color: .fTaxEstimate, width: 10, size: 58)
        }
    }

    /// Полный круг = цель из API; если цели нет — как раньше, от max(доход, расход, налог).
    private func ringFillRatio(actual: Double, target: Double?, fallbackDenominator: Double) -> Double {
        if let t = target, t > 1e-9 {
            return min(max(actual / t, 0), 1)
        }
        return min(max(actual / max(fallbackDenominator, 1e-9), 0), 1)
    }

    private func ring(ratio: Double, color: Color, width: CGFloat, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: width)
            Circle()
                .trim(from: 0, to: CGFloat(ratio))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: width, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }

    private func deltaLabel(_ pct: Double) -> some View {
        let isUp = pct >= 0
        return HStack(spacing: 2) {
            Image(systemName: isUp ? "arrow.up" : "arrow.down")
                .font(.system(size: 8, weight: .bold))
            Text(String(format: "%.0f%%", abs(pct)))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(isUp ? Color.fIncome : Color.fExpense)
    }

    private func deltaPct(_ current: Double, _ previous: Double) -> Double? {
        guard previous != 0 else { return current != 0 ? 100 : nil }
        return ((current - previous) / abs(previous)) * 100
    }

    // MARK: - Section Block

    private func sectionBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.bold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - Managers

    private func managersSection(_ managers: [ManagerSales], revenue: Double) -> some View {
        let maxAmount = managers.first?.amount ?? 1
        return FitnessCard {
            ForEach(Array(managers.enumerated()), id: \.element.id) { idx, m in
                Group {
                    if let pid = m.profileId {
                        NavigationLink(value: HomeLedgerRoute.salesByManager(profileId: pid, title: m.name)) {
                            managerRowContent(idx: idx, m: m, maxAmount: maxAmount, revenue: revenue, showChevron: true)
                        }
                        .buttonStyle(.dashboardPressable)
                    } else {
                        managerRowContent(idx: idx, m: m, maxAmount: maxAmount, revenue: revenue, showChevron: false)
                    }
                }
                .padding(.vertical, 6)
                if idx < managers.count - 1 { Divider().padding(.leading, 46) }
            }
        }
    }

    @ViewBuilder
    private func managerRowContent(idx: Int, m: ManagerSales, maxAmount: Double, revenue: Double, showChevron: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(idx == 0 ? Color.fProfit.opacity(0.15) : Color(.tertiarySystemGroupedBackground))
                    .frame(width: 34, height: 34)
                if idx == 0 {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.fProfit)
                } else {
                    Text("\(idx + 1)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(m.name).font(.subheadline.weight(.medium)).lineLimit(1)
                        .foregroundStyle(.primary)
                    Spacer()
                    if showChevron {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Text(fmt(m.amount)).font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                }
                ProgressBarView(ratio: m.amount / maxAmount, color: .fIncome)
                HStack {
                    Text("\(m.count) продаж").font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Text("от продаж \(pct(m.amount, of: revenue))")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            }
        }
    }

    // MARK: - Points

    private func pointsSection(_ pts: [PointSales], revenue: Double) -> some View {
        let maxAmount = pts.first?.amount ?? 1
        let total = pts.map(\.amount).reduce(0, +)
        return FitnessCard {
            ForEach(Array(pts.enumerated()), id: \.element.id) { idx, p in
                Group {
                    if let pid = p.pointId {
                        NavigationLink(value: HomeLedgerRoute.salesByPoint(pointId: pid, title: p.address)) {
                            pointRowContent(p: p, maxAmount: maxAmount, total: total, revenue: revenue, showChevron: true)
                        }
                        .buttonStyle(.dashboardPressable)
                    } else {
                        pointRowContent(p: p, maxAmount: maxAmount, total: total, revenue: revenue, showChevron: false)
                    }
                }
                .padding(.vertical, 4)
                if idx < pts.count - 1 { Divider() }
            }
        }
    }

    @ViewBuilder
    private func pointRowContent(p: PointSales, maxAmount: Double, total: Double, revenue: Double, showChevron: Bool) -> some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "mappin.circle.fill").font(.subheadline).foregroundStyle(Color.fRevenue)
                Text(p.address).font(.subheadline).lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer()
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(fmt(p.amount)).font(.subheadline.monospacedDigit().weight(.semibold))
                Text(pct(p.amount, of: total))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    .frame(width: 30, alignment: .trailing)
            }
            ProgressBarView(ratio: p.amount / maxAmount, color: .fRevenue)
            Text("от продаж \(pct(p.amount, of: revenue))")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Bank accounts (остатки из выписок / расчёт)

    private static let iso8601UploadWithFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601UploadPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func bankAccountsSnapshotSection(_ accounts: [DashboardBankAccount]) -> some View {
        let sorted = accounts.sorted {
            if $0.bankName.caseInsensitiveCompare($1.bankName) != .orderedSame {
                return $0.bankName.localizedCaseInsensitiveCompare($1.bankName) == .orderedAscending
            }
            return $0.iban.localizedCaseInsensitiveCompare($1.iban) == .orderedAscending
        }
        let anyStale = accounts.contains { $0.isStale }
        return FitnessCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, acc in
                    bankAccountRow(acc, accent: brandColor(for: acc.bankName))
                    if idx < sorted.count - 1 {
                        Divider()
                            .padding(.vertical, 6)
                    }
                }

                if anyStale {
                    Divider()
                        .padding(.vertical, 8)
                    Text(
                        "Дата конца периода в последней выписке старше \(Self.bankBalanceStaleDays) дней — загрузите более свежую, чтобы остаток был актуальным."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func bankAccountRow(_ acc: DashboardBankAccount, accent: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(accent.opacity(0.2))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(acc.bankName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("·")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Text(bankAccountLastFourDigits(acc.iban))
                        .font(.subheadline.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(bankStatementUploadedCaption(iso: acc.lastStatementUploadedAt, hasStatement: acc.hasStatement))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Group {
                if let bal = acc.balance {
                    Text(DashboardMoney.formatTenge(bal))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .multilineTextAlignment(.trailing)
                } else {
                    Button {
                        Task { await chatService.openBankStatementChannelOrChatsTab(preferredIban: acc.iban) }
                    } label: {
                        Text("Загрузить выписку")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .foregroundStyle(.white)
                            .background(Color.red.opacity(0.9))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 148, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private func bankAccountLastFourDigits(_ iban: String) -> String {
        let t = iban.replacingOccurrences(of: " ", with: "")
        guard t.count >= 4 else { return t.isEmpty ? "—" : t }
        return String(t.suffix(4))
    }

    private func bankStatementUploadedCaption(iso: String?, hasStatement: Bool) -> String {
        guard hasStatement else {
            return "Выписка ещё не загружена"
        }
        guard let iso, !iso.isEmpty, let uploaded = Self.iso8601UploadWithFrac.date(from: iso)
                ?? Self.iso8601UploadPlain.date(from: iso) else {
            return "Дата загрузки неизвестна"
        }
        let cal = Calendar.current
        let now = Date()
        if cal.isDateInToday(uploaded) {
            return "Загружено сегодня"
        }
        if cal.isDateInYesterday(uploaded) {
            return "Загружено вчера"
        }
        let d0 = cal.startOfDay(for: uploaded)
        let d1 = cal.startOfDay(for: now)
        guard let daySpan = cal.dateComponents([.day], from: d0, to: d1).day, daySpan > 1 else {
            return "Загружено недавно"
        }
        if daySpan < 7 {
            return "Загружено \(ruDaysAgoPhrase(daySpan))"
        }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        if cal.component(.year, from: uploaded) == cal.component(.year, from: now) {
            fmt.dateFormat = "d MMMM"
        } else {
            fmt.dateFormat = "d MMMM yyyy"
        }
        return "Загружено \(fmt.string(from: uploaded))"
    }

    /// «3 дня назад», «5 дней назад» и т.д. (для фразы «Загружено …»).
    private func ruDaysAgoPhrase(_ n: Int) -> String {
        let mod100 = n % 100
        if mod100 >= 11, mod100 <= 14 {
            return "\(n) дней назад"
        }
        switch n % 10 {
        case 1: return "\(n) день назад"
        case 2, 3, 4: return "\(n) дня назад"
        default: return "\(n) дней назад"
        }
    }

    // MARK: - Income sources (by method / bank)

    private func paymentSourcesSection(_ d: DashboardResponse) -> some View {
        let methods = d.incomeByMethod
        let banks = d.incomeByBank
        let cashPersonal = d.cashIncomePersonal ?? 0
        let cashBusiness = d.cashIncomeBusiness ?? 0
        return Group {
            if !methods.isEmpty {
                paymentMethodsCard(
                    methods,
                    banks: banks,
                    cashPersonal: cashPersonal,
                    cashBusiness: cashBusiness
                )
            } else if !banks.isEmpty {
                // Нет строк способов — показываем банки как раньше (редкий случай)
                bankCardStandalone(banks)
            }
        }
    }

    /// Тап по «Безнал» раскрывает разбивку по банкам; по «Наличные» — личные / бизнес.
    private func paymentMethodTapKind(_ method: String) -> PaymentSourcesExpansion? {
        let m = method.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if m == "наличные" || m.hasPrefix("наличн") { return .cashSplit }
        if m == "безнал" { return .bankBreakdown }
        return nil
    }

    private func togglePaymentSourceExpansion(for method: String) {
        guard let kind = paymentMethodTapKind(method) else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                paymentSourcesExpansion = .none
            }
            return
        }
        DashboardHaptics.lightImpact()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            paymentSourcesExpansion = paymentSourcesExpansion == kind ? .none : kind
        }
    }

    private func paymentMethodsCard(
        _ methods: [MethodAmount],
        banks: [BankAmount],
        cashPersonal: Double,
        cashBusiness: Double
    ) -> some View {
        let total = methods.map(\.amount).reduce(0, +)
        let bankTotal = banks.map(\.amount).reduce(0, +)
        let maxBankAmount = banks.first?.amount ?? 1
        let cashSplitTotal = cashPersonal + cashBusiness
        return FitnessCard {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(methods) { item in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(brandColor(for: item.method))
                            .frame(width: total > 0 ? max(6, geo.size.width * CGFloat(item.amount / total)) : 0)
                    }
                }
            }
            .frame(height: 8)
            .clipShape(.rect(cornerRadius: 4))
            .padding(.bottom, 10)

            ForEach(Array(methods.enumerated()), id: \.element.id) { idx, item in
                let expandable = paymentMethodTapKind(item.method) != nil
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        NavigationLink(value: HomeLedgerRoute.incomeByMethod(methodLabel: item.method)) {
                            HStack(spacing: 8) {
                                Circle().fill(brandColor(for: item.method)).frame(width: 8, height: 8)
                                Text(item.method).font(.subheadline)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                Text(fmt(item.amount)).font(.subheadline.monospacedDigit().weight(.semibold))
                                Text(pct(item.amount, of: total))
                                    .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                    .frame(width: 30, alignment: .trailing)
                            }
                            .padding(.vertical, 4)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.dashboardPressable)

                        if expandable {
                            Button {
                                togglePaymentSourceExpansion(for: item.method)
                            } label: {
                                Image(systemName: chevronForPaymentExpansion(item.method))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 36, height: 44)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if paymentSourcesExpansion == .bankBreakdown,
                       paymentMethodTapKind(item.method) == .bankBreakdown,
                       !banks.isEmpty {
                        incomeBankBreakdownBody(
                            banks: banks,
                            maxAmount: maxBankAmount,
                            ofTotal: bankTotal
                        )
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                    }

                    if paymentSourcesExpansion == .cashSplit,
                       paymentMethodTapKind(item.method) == .cashSplit {
                        cashIncomeSplitBody(
                            personal: cashPersonal,
                            business: cashBusiness,
                            ofTotal: cashSplitTotal
                        )
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                    }
                }
                if idx < methods.count - 1 { Divider().padding(.leading, 16) }
            }
        }
    }

    private func chevronForPaymentExpansion(_ method: String) -> String {
        guard let kind = paymentMethodTapKind(method) else { return "chevron.down" }
        return paymentSourcesExpansion == kind ? "chevron.up" : "chevron.down"
    }

    private func incomeBankBreakdownBody(banks: [BankAmount], maxAmount: Double, ofTotal: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("По банкам")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
                .padding(.bottom, 6)
            ForEach(Array(banks.enumerated()), id: \.element.id) { idx, item in
                let color = brandColor(for: item.bank)
                NavigationLink(value: HomeLedgerRoute.incomeByBank(bankName: item.bank)) {
                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3, height: 22)
                            Text(item.bank).font(.subheadline.weight(.medium))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                            Text(fmt(item.amount)).font(.subheadline.monospacedDigit().weight(.semibold))
                            Text(pct(item.amount, of: ofTotal))
                                .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                .frame(width: 30, alignment: .trailing)
                        }
                        ProgressBarView(ratio: item.amount / maxAmount, color: color)
                    }
                    .padding(.vertical, 4)
                    .padding(.leading, 8)
                }
                .buttonStyle(.dashboardPressable)
                if idx < banks.count - 1 { Divider().padding(.leading, 24) }
            }
        }
    }

    private func cashIncomeSplitBody(personal: Double, business: Double, ofTotal: Double) -> some View {
        let denom = ofTotal > 0 ? ofTotal : 1.0
        return VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 6) {
                NavigationLink(value: HomeLedgerRoute.incomeCashPersonal) {
                    HStack(spacing: 8) {
                        Circle().fill(Color.orange.opacity(0.75)).frame(width: 8, height: 8)
                        Text("Личные")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        Text(fmt(personal))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                        Text(pct(personal, of: denom))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
                .buttonStyle(.dashboardPressable)
                NavigationLink(value: HomeLedgerRoute.incomeCashBusiness) {
                    HStack(spacing: 8) {
                        Circle().fill(Color.fRevenue.opacity(0.9)).frame(width: 8, height: 8)
                        Text("Бизнес")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        Text(fmt(business))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                        Text(pct(business, of: denom))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
                .buttonStyle(.dashboardPressable)
            }
            .padding(.leading, 8)
            Text("Без компании — личные; с компанией — бизнес")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 16)
                .padding(.top, 2)
        }
    }

    private func bankCardStandalone(_ banks: [BankAmount]) -> some View {
        let maxAmount = banks.first?.amount ?? 1
        let total = banks.map(\.amount).reduce(0, +)
        return FitnessCard {
            ForEach(banks) { item in
                let color = brandColor(for: item.bank)
                NavigationLink(value: HomeLedgerRoute.incomeByBank(bankName: item.bank)) {
                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3, height: 22)
                            Text(item.bank).font(.subheadline.weight(.medium))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                            Text(fmt(item.amount)).font(.subheadline.monospacedDigit().weight(.semibold))
                            Text(pct(item.amount, of: total))
                                .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                .frame(width: 30, alignment: .trailing)
                        }
                        ProgressBarView(ratio: item.amount / maxAmount, color: color)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.dashboardPressable)
            }
        }
    }

    // MARK: - Expense account source (ИП vs личные)

    private func expenseAccountSourceSection(_ d: DashboardResponse) -> some View {
        let ip = d.expenseFromIpAccounts ?? 0
        let own = d.expenseFromOwnAccounts ?? 0
        let splitTotal = ip + own
        let maxAmount = max(ip, own, 1)
        return FitnessCard {
            VStack(spacing: 0) {
                NavigationLink(value: HomeLedgerRoute.expenseByAccountSource(isPersonal: false)) {
                    expenseAccountSourceRow(
                        title: "Со счетов ИП",
                        icon: "building.columns.fill",
                        amount: ip,
                        maxAmount: maxAmount,
                        ofTotal: splitTotal,
                        barColor: Color.fExpense
                    )
                }
                .buttonStyle(.dashboardPressable)
                Divider().padding(.leading, 12)
                NavigationLink(value: HomeLedgerRoute.expenseByAccountSource(isPersonal: true)) {
                    expenseAccountSourceRow(
                        title: "С своих счетов",
                        icon: "person.fill",
                        amount: own,
                        maxAmount: maxAmount,
                        ofTotal: splitTotal,
                        barColor: Color.orange.opacity(0.9)
                    )
                }
                .buttonStyle(.dashboardPressable)
            }
        }
    }

    private func expenseAccountSourceRow(
        title: String,
        icon: String,
        amount: Double,
        maxAmount: Double,
        ofTotal: Double,
        barColor: Color
    ) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(barColor)
                Text(title)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text(fmt(amount)).font(.subheadline.monospacedDigit().weight(.semibold))
                Text(pct(amount, of: ofTotal))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    .frame(width: 30, alignment: .trailing)
            }
            ProgressBarView(ratio: amount / maxAmount, color: barColor)
            Text("доля от оплат расходов \(pct(amount, of: ofTotal))")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Expenses

    private func expensesCategorySection(_ categories: [CategoryAmount], revenue: Double) -> some View {
        let total = categories.map(\.amount).reduce(0, +)
        let maxAmount = categories.first?.amount ?? 1
        return FitnessCard {
            ForEach(Array(categories.enumerated()), id: \.element.id) { idx, cat in
                Group {
                    if let cid = cat.categoryId {
                        NavigationLink(value: HomeLedgerRoute.expenseCategory(categoryId: cid, title: cat.category)) {
                            expenseRowContent(cat: cat, maxAmount: maxAmount, total: total, revenue: revenue, showChevron: true)
                        }
                        .buttonStyle(.dashboardPressable)
                    } else {
                        expenseRowContent(cat: cat, maxAmount: maxAmount, total: total, revenue: revenue, showChevron: false)
                    }
                }
                .padding(.vertical, 4)
                if idx < categories.count - 1 { Divider() }
            }
        }
    }

    @ViewBuilder
    private func expenseRowContent(cat: CategoryAmount, maxAmount: Double, total: Double, revenue: Double, showChevron: Bool) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(cat.category).font(.subheadline).lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer()
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(fmt(cat.amount)).font(.subheadline.monospacedDigit().weight(.semibold))
                Text(pct(cat.amount, of: total))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    .frame(width: 30, alignment: .trailing)
            }
            ProgressBarView(ratio: cat.amount / maxAmount, color: .fExpense)
            Text("от продаж \(pct(cat.amount, of: revenue))")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Chart

    private func chartSection(_ points: [ChartPoint]) -> some View {
        FitnessCard {
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Circle().fill(Color.fIncome).frame(width: 7, height: 7)
                    Text("Доход").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.fExpense).frame(width: 7, height: 7)
                    Text("Расход").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Тап по столбцу")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 4)

            let maxVal = points.map { max($0.income, $0.expense) }.max() ?? 1
            /// Мало столбцов — фиксированная ширина и центрирование (как в компактных чартах Apple), не на всю ширину экрана.
            let compactBarLayout = points.count <= 7
            let barColumnWidth: CGFloat = 36

            HStack(alignment: .bottom, spacing: 3) {
                if compactBarLayout {
                    Spacer(minLength: 0)
                }
                ForEach(points) { pt in
                    Button {
                        DashboardHaptics.lightImpact()
                        detailSheet = .chartDay(pt)
                    } label: {
                        VStack(spacing: 2) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.fIncome)
                                .frame(height: max(2, CGFloat(pt.income / maxVal) * 70))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.fExpense)
                                .frame(height: max(2, CGFloat(pt.expense / maxVal) * 70))
                            Text(shortDate(pt.date))
                                .font(.system(size: 7, weight: .medium))
                                .foregroundStyle(.quaternary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(width: compactBarLayout ? barColumnWidth : nil)
                        .frame(maxWidth: compactBarLayout ? barColumnWidth : .infinity)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.dashboardPressable)
                }
                if compactBarLayout {
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 100)
        }
    }

    // MARK: - Period Menu

    private var periodMenu: some View {
        Menu {
            ForEach(DatePeriod.allCases) { period in
                Button {
                    switch period {
                    case .custom:
                        showDatePicker = true
                    case .selectMonth:
                        showMonthPicker = true
                    default:
                        selectedPeriod = period
                    }
                } label: {
                    HStack {
                        Text(period == .monthToDate ? ruMonthYearLabel(for: mtdAnchorMonth) : period.rawValue)
                        if selectedPeriod == period {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "calendar").font(.subheadline)
                Text(periodLabel).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
        }
    }

    private var periodLabel: String {
        switch selectedPeriod {
        case .monthToDate:
            return ruMonthYearLabel(for: mtdAnchorMonth)
        case .today:
            let cal = Calendar.current
            if cal.isDateInToday(todayViewDay) {
                return "Сегодня"
            }
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateFormat = "d MMM yyyy"
            return f.string(from: todayViewDay)
        case .selectMonth:
            return ruMonthYearLabel(for: selectedMonth)
        case .custom:
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateFormat = "d MMM yyyy"
            return f.string(from: customDate)
        }
    }

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker("Дата", selection: $customDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .padding()
                .navigationTitle("Выбрать дату")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { selectedPeriod = .custom; showDatePicker = false }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { showDatePicker = false }
                    }
                }
        }
        .presentationDetents([.medium])
    }

    private var monthPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Отчёт за полный календарный месяц")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                HStack(spacing: 12) {
                    Picker("Месяц", selection: $pickMonth) {
                        ForEach(1...12, id: \.self) { m in
                            Text(monthPickerLabel(month: m)).tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Picker("Год", selection: $pickYear) {
                        ForEach(monthPickerYearRange, id: \.self) { y in
                            Text(String(y)).tag(y)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
                .environment(\.locale, Locale(identifier: "ru_RU"))
            }
            .padding()
            .navigationTitle("Выбрать месяц")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                let cal = Calendar.current
                let c = cal.dateComponents([.year, .month], from: selectedMonth)
                pickMonth = c.month ?? 1
                pickYear = c.year ?? cal.component(.year, from: Date())
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        let cal = Calendar.current
                        if let first = cal.date(from: DateComponents(year: pickYear, month: pickMonth, day: 1)) {
                            selectedMonth = first
                        }
                        selectedPeriod = .selectMonth
                        showMonthPicker = false
                        loadData()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { showMonthPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var monthPickerYearRange: [Int] {
        let y = Calendar.current.component(.year, from: Date())
        return Array((y - 12)...(y + 1))
    }

    private func monthPickerLabel(month: Int) -> String {
        let cal = Calendar.current
        guard let d = cal.date(from: DateComponents(year: 2000, month: month, day: 1)) else {
            return "\(month)"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL"
        return f.string(from: d).capitalized
    }

    // MARK: - States

    private var loadingPlaceholder: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)).frame(height: 150)
            HStack(spacing: 10) {
                ForEach(0..<3) { _ in
                    RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)).frame(height: 64)
                }
            }
            RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)).frame(height: 100)
        }
        .padding(16)
        .redacted(reason: .placeholder)
        .shimmer()
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 40)).foregroundStyle(.quaternary)
            Text("Не удалось загрузить").font(.headline)
            Text(msg).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { loadData() } label: {
                Text("Повторить").font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(.tint, in: Capsule()).foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300).padding()
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 40)).foregroundStyle(.quaternary)
            Text("Нет ответа от сервера").font(.headline)
            Text("Потяните вниз для обновления или проверьте подключение.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(.horizontal, 24)
    }

    // MARK: - Data

    private func loadData() { Task { await loadDataAsync() } }

    private func loadDataAsync() async {
        paymentSourcesExpansion = .none
        ledgerPath = NavigationPath()
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var dateStr: String?
            let dayFmt = DateFormatter()
            dayFmt.dateFormat = "yyyy-MM-dd"
            switch selectedPeriod {
            case .custom:
                dateStr = dayFmt.string(from: customDate)
            case .selectMonth:
                dateStr = monthFirstDayISO(from: selectedMonth)
            case .today:
                dateStr = dayFmt.string(from: todayViewDay)
            case .monthToDate:
                dateStr = monthFirstDayISO(from: mtdAnchorMonth)
            }
            async let dashboardTask = APIService.shared.dashboard(period: selectedPeriod.apiValue, date: dateStr)
            async let branchesList = branchesLoadOptional()
            async let teamSnap = teamLoadOptional()
            let loaded = try await dashboardTask
            let br = await branchesList
            let tm = await teamSnap
            let picked = DashboardDisplayTax.pickPrimaryBranch(
                branches: br ?? [],
                team: tm,
                userEmail: appState.user?.email
            )
            await MainActor.run {
                primaryBranch = picked
                dashboard = loaded
                if loaded.bankAccounts?.isEmpty != false {
                    expandedBankAccountsUnderOstatok = false
                }
            }
        } catch is CancellationError {
            // Потянули refresh или сменили вкладку — не показываем ошибку.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func branchesLoadOptional() async -> [BranchCompany]? {
        try? await APIService.shared.branches()
    }

    private func teamLoadOptional() async -> TeamSnapshot? {
        try? await APIService.shared.teamSnapshot()
    }

    // MARK: - Helpers

    private func fmt(_ v: Double) -> String { DashboardMoney.formatTenge(v) }

    private func fmtShort(_ v: Double) -> String { DashboardMoney.formatShortTenge(v) }

    private func pct(_ v: Double, of total: Double) -> String { DashboardMoney.percent(v, of: total) }

    private func shortDate(_ iso: String) -> String { DashboardMoney.shortDateLabel(iso) }
}

// MARK: - MetricRow (Fitness-style)

private struct MetricRow: View {
    let label: String
    let value: Double
    let tint: Color
    var delta: Double?
    var subtitle: String? = nil
    var showApproximateBadge: Bool = false
    /// Белый текст на тёмном фоне (колонки «Доход» / «Расход» на главной).
    var lightOnDark: Bool = false
    /// Цвет крупной суммы; если `nil` — как `valueColor`.
    var amountColor: Color? = nil
    var onTap: (() -> Void)? = nil

    private var cardFill: Color {
        lightOnDark
            ? Color(red: 0.14, green: 0.14, blue: 0.16)
            : Color(.secondarySystemGroupedBackground)
    }

    private var labelColor: Color {
        lightOnDark ? .white : tint
    }

    private var valueColor: Color {
        lightOnDark ? .white : .primary
    }

    private var tertiaryOnCard: Color {
        lightOnDark ? Color.white.opacity(0.62) : Color(.tertiaryLabel)
    }

    private var mainAmountColor: Color {
        amountColor ?? valueColor
    }

    var body: some View {
        let inner = VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 4) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(labelColor)
                if showApproximateBadge {
                    Text("≈")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(lightOnDark ? Color.white.opacity(0.7) : .secondary)
                        .accessibilityLabel("Ориентировочная оценка")
                }
                Spacer(minLength: 0)
                if onTap != nil {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(tertiaryOnCard)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .topLeading)
            Text(shortVal)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(mainAmountColor)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(tertiaryOnCard)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let delta {
                let isUp = delta >= 0
                HStack(spacing: 2) {
                    Image(systemName: isUp ? "arrow.up" : "arrow.down")
                        .font(.system(size: 7, weight: .bold))
                    Text(String(format: "%.0f%%", abs(delta)))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(lightOnDark ? .white : (isUp ? Color.fIncome : Color.fExpense))
            } else {
                Text(" ")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .hidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(cardFill, in: .rect(cornerRadius: 12))

        Group {
            if let onTap {
                Button(action: onTap) {
                    inner
                }
                .buttonStyle(.dashboardPressable)
            } else {
                inner
            }
        }
    }

    private var shortVal: String { DashboardMoney.formatCompact(value) }
}

// MARK: - ProgressBarView

private struct ProgressBarView: View {
    let ratio: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.08))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.35))
                    .frame(width: geo.size.width * min(CGFloat(ratio), 1.0))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Period swipe (целиком по ленте дашборда)

private struct PeriodSwipeGlow: View {
    var progress: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { g in
            let w = max(g.size.width, 1)
            let h = max(g.size.height, 1)
            let p = Double(progress)
            let strength = pow(min(1, abs(p)), 1.1)

            let c = 0.5 + p * 0.36
            let wing = 0.15
            let lo = max(0, min(1, c - wing))
            let hi = max(0, min(1, c + wing))
            let mid = max(lo, min(hi, c))

            let peak = colorScheme == .dark ? 0.11 : 0.19

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.white.opacity(peak * 0.38), location: lo),
                    .init(color: Color.white.opacity(peak), location: mid),
                    .init(color: Color.white.opacity(peak * 0.38), location: hi),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: w, height: h)
            .blendMode(.plusLighter)
            .opacity(strength * 0.36)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - FitnessCard

private struct FitnessCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }
}

// MARK: - Shimmer

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    func body(content: Content) -> some View {
        content.overlay(
            LinearGradient(colors: [.clear, .white.opacity(0.12), .clear],
                           startPoint: .init(x: phase - 0.5, y: 0.5),
                           endPoint: .init(x: phase + 0.5, y: 0.5))
            .blendMode(.sourceAtop)
        ).onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) { phase = 1.5 }
        }
    }
}

private extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}

#Preview {
    HomeView()
        .environment(AppState())
        .environment(ChatService())
}
