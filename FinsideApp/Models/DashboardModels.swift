import Foundation

struct DashboardResponse: Decodable {
    let period: PeriodInfo
    let summary: DashboardSummary
    let comparison: PeriodComparison
    /// Цели для колец: месячные — факт прошлого месяца; день — среднее MTD за месяц до выбранного дня.
    let ringTargets: RingTargets?
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
    let expensesByCategory: [CategoryAmount]
    let chart: [ChartPoint]
    /// Счета и остатки из последних выписок (см. `closing_balance` на загрузке).
    let bankAccounts: [DashboardBankAccount]?

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
        case expensesByCategory = "expenses_by_category"
        case bankAccounts = "bank_accounts"
    }
}

struct DashboardBankAccount: Decodable, Identifiable, Hashable {
    let id: Int
    let iban: String
    let bankName: String
    let bankCode: String
    /// Итог для отображения: из выписки или расчёт на бэкенде.
    let balance: Double?
    /// `statement` | `computed_opening` | `computed_anchor`
    let balanceSource: String?
    let balanceAsOf: String?
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
        lastStatementUploadedAt = try c.decodeIfPresent(String.self, forKey: .lastStatementUploadedAt)
        hasStatement = try c.decodeIfPresent(Bool.self, forKey: .hasStatement) ?? false
        isStale = try c.decodeIfPresent(Bool.self, forKey: .isStale) ?? true
    }
}

struct RingTargets: Codable {
    let income: Double
    let expense: Double
    let tax: Double
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

    enum CodingKeys: String, CodingKey {
        case prevIncome = "prev_income"
        case prevExpense = "prev_expense"
        case prevProfit = "prev_profit"
        case prevRevenue = "prev_revenue"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prevIncome = try c.decode(Double.self, forKey: .prevIncome)
        prevExpense = try c.decode(Double.self, forKey: .prevExpense)
        prevProfit = try c.decode(Double.self, forKey: .prevProfit)
        prevRevenue = try c.decodeIfPresent(Double.self, forKey: .prevRevenue) ?? 0
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
