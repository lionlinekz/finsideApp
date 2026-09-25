import Foundation

/// Плановые и согласованные обязательства к оплате (дашборд API).
/// Статистика запросов на согласование за период дашборда.
struct DashboardApprovalStats: Decodable, Equatable {
    let total: Int
    let approved: Int
    let rejected: Int
    let pendingInPeriod: Int
    let pendingActionCount: Int
    let periodItems: [DashboardApprovalItem]
    let pendingActionItems: [DashboardApprovalItem]

    enum CodingKeys: String, CodingKey {
        case total, approved, rejected
        case pendingInPeriod = "pending_in_period"
        case pendingActionCount = "pending_action_count"
        case periodItems = "period_items"
        case pendingActionItems = "pending_action_items"
    }

    init(
        total: Int,
        approved: Int,
        rejected: Int,
        pendingInPeriod: Int,
        pendingActionCount: Int,
        periodItems: [DashboardApprovalItem],
        pendingActionItems: [DashboardApprovalItem]
    ) {
        self.total = total
        self.approved = approved
        self.rejected = rejected
        self.pendingInPeriod = pendingInPeriod
        self.pendingActionCount = pendingActionCount
        self.periodItems = periodItems
        self.pendingActionItems = pendingActionItems
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        approved = try c.decodeIfPresent(Int.self, forKey: .approved) ?? 0
        rejected = try c.decodeIfPresent(Int.self, forKey: .rejected) ?? 0
        pendingInPeriod = try c.decodeIfPresent(Int.self, forKey: .pendingInPeriod) ?? 0
        pendingActionCount = try c.decodeIfPresent(Int.self, forKey: .pendingActionCount) ?? 0
        periodItems = (try? c.decode([DashboardApprovalItem].self, forKey: .periodItems)) ?? []
        pendingActionItems = (try? c.decode([DashboardApprovalItem].self, forKey: .pendingActionItems)) ?? []
    }

    static let empty = DashboardApprovalStats(
        total: 0,
        approved: 0,
        rejected: 0,
        pendingInPeriod: 0,
        pendingActionCount: 0,
        periodItems: [],
        pendingActionItems: []
    )

    /// Запросы, которые нужно подсветить на главной (ожидают решения или согласования).
    var highlightedPendingItems: [DashboardApprovalItem] {
        if !pendingActionItems.isEmpty { return pendingActionItems }
        return periodItems.filter {
            $0.approvalStatus == .pending && ($0.outsidePeriod || $0.needsAction)
        }
    }

    var hasVisibleActivity: Bool {
        total > 0 || pendingActionCount > 0 || !highlightedPendingItems.isEmpty
    }

    /// Подставить ожидающие согласования из чата, если API их не вернул.
    func enriched(withPending pending: [PendingApprovalItem]) -> DashboardApprovalStats {
        guard pendingActionCount == 0, !pending.isEmpty else { return self }
        let items = pending.map { DashboardApprovalItem(pending: $0) }
        return DashboardApprovalStats(
            total: max(total, pending.count),
            approved: approved,
            rejected: rejected,
            pendingInPeriod: max(pendingInPeriod, pending.count),
            pendingActionCount: pending.count,
            periodItems: periodItems.isEmpty ? items : periodItems,
            pendingActionItems: items
        )
    }

    static func fromPendingApprovals(_ pending: [PendingApprovalItem]) -> DashboardApprovalStats {
        let items = pending.map { DashboardApprovalItem(pending: $0) }
        return DashboardApprovalStats(
            total: 0,
            approved: 0,
            rejected: 0,
            pendingInPeriod: 0,
            pendingActionCount: pending.count,
            periodItems: [],
            pendingActionItems: items
        )
    }
}

/// Строка списка согласований (дашборд API).
struct DashboardApprovalItem: Codable, Identifiable, Hashable {
    let id: Int
    let conversationId: Int
    let senderId: Int?
    let senderName: String
    let text: String
    let payload: MessagePayload
    let createdAt: String
    let approvalStatus: ApprovalStatus?
    let conversationTitle: String
    let outsidePeriod: Bool
    let needsAction: Bool

    enum CodingKeys: String, CodingKey {
        case id, text, payload
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case senderName = "sender_name"
        case createdAt = "created_at"
        case approvalStatus = "approval_status"
        case conversationTitle = "conversation_title"
        case outsidePeriod = "outside_period"
        case needsAction = "needs_action"
    }

    var formattedAmount: String {
        guard let amountStr = payload.amount,
              let amount = MoneyAmount(fromString: amountStr) else { return "" }
        return amount.formattedWithCurrency
    }

    var displayTitle: String {
        if !conversationTitle.isEmpty { return conversationTitle }
        if !senderName.isEmpty { return senderName }
        return "Согласование"
    }

    init(
        id: Int,
        conversationId: Int,
        senderId: Int? = nil,
        senderName: String,
        text: String,
        payload: MessagePayload,
        createdAt: String,
        approvalStatus: ApprovalStatus?,
        conversationTitle: String,
        outsidePeriod: Bool,
        needsAction: Bool
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.senderName = senderName
        self.text = text
        self.payload = payload
        self.createdAt = createdAt
        self.approvalStatus = approvalStatus
        self.conversationTitle = conversationTitle
        self.outsidePeriod = outsidePeriod
        self.needsAction = needsAction
    }

    init(pending: PendingApprovalItem) {
        self.init(
            id: pending.id,
            conversationId: pending.conversationId,
            senderName: pending.senderName,
            text: pending.text,
            payload: pending.payload,
            createdAt: pending.createdAt,
            approvalStatus: .pending,
            conversationTitle: pending.conversationTitle,
            outsidePeriod: true,
            needsAction: true
        )
    }

    var approvalSnapshot: ApprovalSnapshot {
        ApprovalSnapshot(
            senderId: senderId,
            senderName: senderName,
            text: text,
            payload: payload,
            createdAt: createdAt,
            approvalStatus: approvalStatus
        )
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        conversationId = try c.decode(Int.self, forKey: .conversationId)
        senderId = try c.decodeIfPresent(Int.self, forKey: .senderId)
        senderName = try c.decodeIfPresent(String.self, forKey: .senderName) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        payload = try c.decodeIfPresent(MessagePayload.self, forKey: .payload) ?? MessagePayload()
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        approvalStatus = try c.decodeIfPresent(ApprovalStatus.self, forKey: .approvalStatus)
        conversationTitle = try c.decodeIfPresent(String.self, forKey: .conversationTitle) ?? ""
        outsidePeriod = try c.decodeIfPresent(Bool.self, forKey: .outsidePeriod) ?? false
        needsAction = try c.decodeIfPresent(Bool.self, forKey: .needsAction) ?? false
    }
}

struct DashboardApprovalStatsResponse: Decodable {
    let approvalStats: DashboardApprovalStats

    enum CodingKeys: String, CodingKey {
        case approvalStats = "approval_stats"
    }
}

struct DashboardCashCommitments: Codable, Equatable {
    let plannedWaitingTotal: Double
    let approvedUnpaidTotal: Double
    let total: Double

    enum CodingKeys: String, CodingKey {
        case plannedWaitingTotal = "planned_waiting_total"
        case approvedUnpaidTotal = "approved_unpaid_total"
        case total
    }
}

struct DashboardResponse: Decodable {
    let period: PeriodInfo
    let summary: DashboardSummary
    let comparison: PeriodComparison
    /// Цели для колец: месячные — факт прошлого месяца; день — среднее MTD за месяц до выбранного дня.
    let ringTargets: RingTargets?
    /// Плановые платежи (WAITING) + согласованные в чате без `payment_id`.
    let cashCommitments: DashboardCashCommitments?
    let approvalStats: DashboardApprovalStats?
    let managers: [ManagerSales]
    let points: [PointSales]
    let incomeByMethod: [MethodAmount]
    let incomeByCategory: [CategoryAmount]
    let incomeByBank: [BankAmount]
    /// Сумма наличных доходов без привязки к компании (личные)
    let cashIncomePersonal: Double?
    /// Сумма наличных доходов с компанией (бизнес)
    let cashIncomeBusiness: Double?
    /// Расходы, списанные со счетов ИП (оборотные; `is_personal_money == false`).
    let expenseFromIpAccounts: Double?
    /// Расходы с личных счетов (`is_personal_money == true`).
    let expenseFromOwnAccounts: Double?
    /// Разбивка оплат расходов по счёту (банк + хвост IBAN из выписки и т.д.).
    let expenseByAccount: [DashboardExpenseAccountRow]?
    /// Разбивка расходов по филиалам (компаниям из накладной).
    let expensesByBranch: [DashboardBranchExpense]?
    let expensesByCategory: [CategoryAmount]
    let chart: [ChartPoint]
    /// Счета и остатки из последних выписок (см. `closing_balance` на загрузке).
    let bankAccounts: [DashboardBankAccount]?
    /// Кассы точек (наличные) с последним внесённым остатком.
    let cashRegisters: [CashRegister]?
    /// Сумма известных остатков по кассам.
    let cashBalanceTotal: Double?
    /// Сколько касс имеют внесённый остаток.
    let cashBalanceKnownCount: Int?
    /// Может ли текущий пользователь вносить остатки (право UPLOAD_BALANCE).
    let canUploadBalance: Bool?

    enum CodingKeys: String, CodingKey {
        case period, summary, comparison, managers, points, chart
        case ringTargets = "ring_targets"
        case incomeByMethod = "income_by_method"
        case incomeByCategory = "income_by_category"
        case incomeByBank = "income_by_bank"
        case cashIncomePersonal = "cash_income_personal"
        case cashIncomeBusiness = "cash_income_business"
        case expenseFromIpAccounts = "expense_from_ip_accounts"
        case expenseFromOwnAccounts = "expense_from_own_accounts"
        case expenseByAccount = "expense_by_account"
        case expensesByBranch = "expenses_by_branch"
        case expensesByCategory = "expenses_by_category"
        case bankAccounts = "bank_accounts"
        case cashRegisters = "cash_registers"
        case cashBalanceTotal = "cash_balance_total"
        case cashBalanceKnownCount = "cash_balance_known_count"
        case canUploadBalance = "can_upload_balance"
        case cashCommitments = "cash_commitments"
        case approvalStats = "approval_stats"
    }
}

/// Строка блока «Оплаты расходов» на дашборде + параметры drill-down в ledger API.
struct DashboardExpenseAccountRow: Decodable, Identifiable, Hashable {
    let label: String
    let bank: String
    let accountSuffix: String?
    let isPersonal: Bool
    let amount: Double
    let bankStatementUploadId: Int?
    let paymentBankFilter: String?
    let cashOnly: Bool

    var id: String {
        let u = bankStatementUploadId.map(String.init) ?? "-"
        let pb = paymentBankFilter ?? ""
        return "\(u)|\(pb)|\(cashOnly)|\(isPersonal)|\(label)"
    }

    enum CodingKeys: String, CodingKey {
        case label, bank, amount
        case accountSuffix = "account_suffix"
        case isPersonal = "is_personal"
        case bankStatementUploadId = "bank_statement_upload_id"
        case paymentBankFilter = "payment_bank_filter"
        case cashOnly = "cash_only"
    }
}

/// Строка блока «Расходы по филиалам» на дашборде.
/// `branchId == nil` — «Без филиала» (платежи без накладной).
struct DashboardBranchExpense: Decodable, Identifiable, Hashable {
    let branchId: Int?
    let name: String
    let amount: Double

    var id: String {
        if let branchId { return "b-\(branchId)" }
        return "b-none"
    }

    enum CodingKeys: String, CodingKey {
        case branchId = "branch_id"
        case name
        case amount
    }
}

struct DashboardBankAccount: Decodable, Identifiable, Hashable {
    let id: Int
    let iban: String
    let bankName: String
    let bankCode: String
    /// Итог для отображения: из выписки или расчёт на бэкенде.
    let balance: Double?
    /// `statement` | `computed_snapshot` | legacy `computed_opening`
    let balanceSource: String?
    let balanceAsOf: String?
    let anchorSnapshotDate: String?
    /// Когда файл последней выписки был загружен (ISO 8601).
    let lastStatementUploadedAt: String?
    let hasStatement: Bool
    let isStale: Bool

    enum CodingKeys: String, CodingKey {
        case id, iban
        case bankName = "bank_name"
        case bankCode = "bank_code"
        case balance
        case balanceSource = "balance_source"
        case balanceAsOf = "balance_as_of"
        case anchorSnapshotDate = "anchor_snapshot_date"
        case lastStatementUploadedAt = "last_statement_uploaded_at"
        case hasStatement = "has_statement"
        case isStale = "is_stale"
        case closingBalance = "closing_balance"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        iban = try c.decode(String.self, forKey: .iban)
        bankName = try c.decode(String.self, forKey: .bankName)
        bankCode = try c.decodeIfPresent(String.self, forKey: .bankCode) ?? ""
        if let b = try c.decodeIfPresent(Double.self, forKey: .balance) {
            balance = b
        } else {
            balance = try c.decodeIfPresent(Double.self, forKey: .closingBalance)
        }
        balanceSource = try c.decodeIfPresent(String.self, forKey: .balanceSource)
        balanceAsOf = try c.decodeIfPresent(String.self, forKey: .balanceAsOf)
        anchorSnapshotDate = try c.decodeIfPresent(String.self, forKey: .anchorSnapshotDate)
        lastStatementUploadedAt = try c.decodeIfPresent(String.self, forKey: .lastStatementUploadedAt)
        hasStatement = try c.decodeIfPresent(Bool.self, forKey: .hasStatement) ?? false
        isStale = try c.decodeIfPresent(Bool.self, forKey: .isStale) ?? true
    }
}

/// Касса точки (наличные). `pointId == nil` — «Общая касса».
/// Остаток вводится вручную, поэтому может отсутствовать (`balance == nil`).
struct CashRegister: Decodable, Identifiable, Hashable {
    let pointId: Int?
    let label: String
    let companyName: String?
    let balance: Double?
    let balanceDate: String?
    let hasBalance: Bool

    var id: String {
        if let pointId { return "p-\(pointId)" }
        return "general"
    }

    enum CodingKeys: String, CodingKey {
        case pointId = "point_id"
        case label
        case companyName = "company_name"
        case balance
        case balanceDate = "balance_date"
        case hasBalance = "has_balance"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pointId = try c.decodeIfPresent(Int.self, forKey: .pointId)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? "Касса"
        companyName = try c.decodeIfPresent(String.self, forKey: .companyName)
        balance = try c.decodeIfPresent(Double.self, forKey: .balance)
        balanceDate = try c.decodeIfPresent(String.self, forKey: .balanceDate)
        hasBalance = try c.decodeIfPresent(Bool.self, forKey: .hasBalance) ?? (balance != nil)
    }

    init(pointId: Int?, label: String, companyName: String?, balance: Double?, balanceDate: String?, hasBalance: Bool) {
        self.pointId = pointId
        self.label = label
        self.companyName = companyName
        self.balance = balance
        self.balanceDate = balanceDate
        self.hasBalance = hasBalance
    }
}

/// Ответ POST /api/cash-balances/save/ — обновлённая касса.
struct CashBalanceSaveResponse: Decodable {
    let ok: Bool
    let register: CashRegister
}

/// Ответ GET /api/cash-balances/ — список касс с правами на редактирование.
struct CashRegistersResponse: Decodable {
    let registers: [CashRegister]
    let total: Double?
    let knownCount: Int?
    let canUploadBalance: Bool
    let asOf: String?

    enum CodingKeys: String, CodingKey {
        case registers
        case total
        case knownCount = "known_count"
        case canUploadBalance = "can_upload_balance"
        case asOf = "as_of"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        registers = try c.decodeIfPresent([CashRegister].self, forKey: .registers) ?? []
        total = try c.decodeIfPresent(Double.self, forKey: .total)
        knownCount = try c.decodeIfPresent(Int.self, forKey: .knownCount)
        canUploadBalance = try c.decodeIfPresent(Bool.self, forKey: .canUploadBalance) ?? false
        asOf = try c.decodeIfPresent(String.self, forKey: .asOf)
    }
}

struct RingTargets: Codable {
    let income: Double
    let expense: Double
    let tax: Double
    let revenue: Double?
    let balance: Double?

    enum CodingKeys: String, CodingKey {
        case income, expense, tax, revenue, balance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        income = try c.decode(Double.self, forKey: .income)
        expense = try c.decode(Double.self, forKey: .expense)
        tax = try c.decodeIfPresent(Double.self, forKey: .tax) ?? 0
        revenue = try c.decodeIfPresent(Double.self, forKey: .revenue)
        balance = try c.decodeIfPresent(Double.self, forKey: .balance)
    }
}

struct PeriodInfo: Codable {
    let start: String
    let end: String
    let type: String
}

struct DashboardSummary: Codable {
    let totalIncome: Double
    let totalExpense: Double
    let totalTransfer: Double
    let revenue: Double
    let profit: Double
    /// Сумма остатков по счетам (включая устаревшие выписки).
    let bankBalanceTotal: Double?
    let bankBalanceKnown: Bool?
    let bankBalanceAsOf: String?
    let bankBalanceAccountsIncluded: Int?
    /// Хотя бы один счёт в сумме имеет выписку старше 14 дней.
    let bankBalanceIsStale: Bool?
    let incomeCount: Int
    let expenseCount: Int
    /// Оценка налога (сервер: режим компании или 3% продаж)
    let potentialTax: Double?
    let potentialTaxHint: String?
    let potentialTaxIsApproximate: Bool?
    /// Код режима (PATENT / USN / OUR / …) с бэкенда
    let taxRegimeCode: String?
    /// period | legacy | default
    let taxRegimeSource: String?
    let taxRegimeTitleRu: String?
    let taxRegimeSourceLabelRu: String?

    enum CodingKeys: String, CodingKey {
        case totalIncome = "total_income"
        case totalExpense = "total_expense"
        case totalTransfer = "total_transfer"
        case revenue, profit
        case bankBalanceTotal = "bank_balance_total"
        case bankBalanceKnown = "bank_balance_known"
        case bankBalanceAsOf = "bank_balance_as_of"
        case bankBalanceAccountsIncluded = "bank_balance_accounts_included"
        case bankBalanceIsStale = "bank_balance_is_stale"
        case incomeCount = "income_count"
        case expenseCount = "expense_count"
        case potentialTax = "potential_tax"
        case potentialTaxHint = "potential_tax_hint"
        case potentialTaxIsApproximate = "potential_tax_is_approximate"
        case taxRegimeCode = "tax_regime_code"
        case taxRegimeSource = "tax_regime_source"
        case taxRegimeTitleRu = "tax_regime_title_ru"
        case taxRegimeSourceLabelRu = "tax_regime_source_label_ru"
    }

    /// Сумма для карточки; fallback 3% продаж если API старый
    var resolvedPotentialTax: Double {
        if let t = potentialTax { return t }
        return revenue * 0.03
    }

    var resolvedPotentialTaxHint: String {
        if let h = potentialTaxHint, !h.isEmpty { return h }
        return "≈ 3% от продаж (оценка)"
    }

    var resolvedTaxIsApproximate: Bool {
        potentialTaxIsApproximate ?? true
    }
}

struct PeriodComparison: Codable {
    let prevIncome: Double
    let prevExpense: Double
    let prevProfit: Double
    /// Продажи (SALES) за предыдущий период — для строки «Доход» при отображении выручки.
    let prevRevenue: Double
    let prevBankBalanceTotal: Double?

    enum CodingKeys: String, CodingKey {
        case prevIncome = "prev_income"
        case prevExpense = "prev_expense"
        case prevProfit = "prev_profit"
        case prevRevenue = "prev_revenue"
        case prevBankBalanceTotal = "prev_bank_balance_total"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prevIncome = try c.decode(Double.self, forKey: .prevIncome)
        prevExpense = try c.decode(Double.self, forKey: .prevExpense)
        prevProfit = try c.decode(Double.self, forKey: .prevProfit)
        prevRevenue = try c.decodeIfPresent(Double.self, forKey: .prevRevenue) ?? 0
        prevBankBalanceTotal = try c.decodeIfPresent(Double.self, forKey: .prevBankBalanceTotal)
    }
}

extension DashboardSummary {
    /// Денежный остаток для главной: сумма по банковским счетам, если известна.
    var resolvedBankBalanceTotal: Double? {
        if bankBalanceKnown == false { return nil }
        return bankBalanceTotal
    }

    /// Сумма остатков: сначала по счетам, иначе из summary API.
    func resolvedBankBalanceTotal(accounts: [DashboardBankAccount]?) -> Double? {
        let fromAccounts = (accounts ?? []).compactMap(\.balance)
        if !fromAccounts.isEmpty {
            return fromAccounts.reduce(0, +)
        }
        return resolvedBankBalanceTotal
    }

    /// Остаток основан на выписках старше 14 дней (ориентир, не актуальный баланс).
    func resolvedBankBalanceIsStale(accounts: [DashboardBankAccount]?) -> Bool {
        if bankBalanceIsStale == true { return true }
        let withBalance = (accounts ?? []).filter { $0.balance != nil }
        return withBalance.contains { $0.isStale }
    }

    /// Остаток основан на выписках старше 14 дней (ориентир, не актуальный баланс).
    var resolvedBankBalanceIsStale: Bool {
        bankBalanceIsStale ?? false
    }
}

struct ManagerSales: Codable, Identifiable {
    let profileId: Int?
    let name: String
    let amount: Double
    let count: Int

    enum CodingKeys: String, CodingKey {
        case profileId = "profile_id"
        case name, amount, count
    }

    var id: String {
        if let profileId { return "m-\(profileId)" }
        return "m-\(name)"
    }
}

struct PointSales: Codable, Identifiable {
    let pointId: Int?
    let address: String
    let amount: Double

    enum CodingKeys: String, CodingKey {
        case pointId = "point_id"
        case address, amount
    }

    var id: String {
        if let pointId { return "p-\(pointId)" }
        return "p-\(address)"
    }
}

struct MethodAmount: Codable, Identifiable {
    let method: String
    let amount: Double
    var id: String { method }
}

struct CategoryAmount: Codable, Identifiable {
    let categoryId: Int?
    let category: String
    let amount: Double

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case category, amount
    }

    var id: String {
        if let categoryId { return "c-\(categoryId)" }
        return "c-\(category)"
    }
}

struct BankAmount: Codable, Identifiable {
    let bank: String
    let amount: Double
    var id: String { bank }
}

struct ChartPoint: Codable, Identifiable {
    let date: String
    let income: Double
    let expense: Double
    var id: String { date }
}
