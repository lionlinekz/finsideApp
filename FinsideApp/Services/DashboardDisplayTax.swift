import Foundation

/// Оценка налога на главной: значение `potential_tax` с API (если есть),
/// иначе эффективная ставка из `/branches/`, иначе код режима из summary / tax_mode компании.
enum DashboardDisplayTax {
    /// База «с выручки» в ответе API и филиала — для оценки в UI совпадает с **всеми поступлениями**
    /// за период (`total_income`), не только категорией SALES.
    private static func taxBaseFromAllReceipts(_ summary: DashboardSummary) -> Double {
        summary.totalIncome
    }

    static func compute(
        summary: DashboardSummary,
        primaryBranch: BranchCompany?
    ) -> (amount: Double, hint: String) {
        let receiptsBase = taxBaseFromAllReceipts(summary)
        if let server = summary.potentialTax {
            let code = summary.taxRegimeCode?.uppercased() ?? ""
            let profitBased = code == "OUR" || code == "TOO_CIT_GENERAL"
            let likelyStaleZero = !profitBased
                && server <= 0
                && summary.revenue <= 0
                && summary.totalIncome > 0
            if !likelyStaleZero {
                let hint = hintWhenServer(summary: summary, branch: primaryBranch)
                return (server, hint)
            }
        }
        if let branch = primaryBranch, let computed = computeFromBranch(summary: summary, branch: branch) {
            return computed
        }
        return amountForRegimeCode(
            summary.taxRegimeCode,
            revenue: receiptsBase,
            profit: summary.profit
        )
    }

    private static func hintWhenServer(
        summary: DashboardSummary,
        branch: BranchCompany?
    ) -> String {
        if let h = summary.potentialTaxHint, !h.isEmpty { return h }
        if let b = branch, !b.taxModeLabel.isEmpty {
            return "Режим: \(b.taxModeLabel)"
        }
        return amountForRegimeCode(
            summary.taxRegimeCode,
            revenue: taxBaseFromAllReceipts(summary),
            profit: summary.profit
        ).hint
    }

    private static func computeFromBranch(
        summary: DashboardSummary,
        branch: BranchCompany
    ) -> (Double, String)? {
        let receiptsBase = taxBaseFromAllReceipts(summary)
        if let rate = branch.taxRate, rate >= 0 {
            let base = (branch.taxCalculationBase ?? "revenue").lowercased()
            let raw: Double
            if base == "profit" {
                raw = max(0, summary.profit) * rate
            } else {
                raw = receiptsBase * rate
            }
            let amount = roundMoney(raw)
            let baseRu = base == "profit" ? "денежного остатка" : "поступлений"
            let pct = Int(round(branch.taxRatePercent ?? rate * 100))
            let label = branch.taxModeLabel
            if !label.isEmpty {
                return (amount, "За выбранный период: \(label) (\(pct)% с \(baseRu))")
            }
            return (amount, "За выбранный период: \(pct)% с \(baseRu)")
        }
        if let rc = branch.taxRegimeCode, !rc.trimmingCharacters(in: .whitespaces).isEmpty {
            let pair = amountForRegimeCode(rc, revenue: receiptsBase, profit: summary.profit)
            return (pair.amount, "За период (из компании). " + pair.hint)
        }
        if !branch.taxMode.isEmpty {
            let pair = amountForRegimeCode(branch.taxMode, revenue: receiptsBase, profit: summary.profit)
            let name = branch.taxModeLabel
            if !name.isEmpty {
                return (pair.amount, "За период: \(name). " + pair.hint)
            }
            return (pair.amount, "За период. " + pair.hint)
        }
        return nil
    }

    private static func amountForRegimeCode(
        _ code: String?,
        revenue: Double,
        profit: Double
    ) -> (amount: Double, hint: String) {
        let c = code?.uppercased().trimmingCharacters(in: .whitespaces) ?? ""
        let r = revenue
        let p = profit
        switch c {
        case "PATENT", "IP_SNR_PATENT":
            return (roundMoney(r * 0.01), "≈ 1% от поступлений (оценка)")
        case "USN", "IP_USN_DECLARATION":
            return (roundMoney(r * 0.03), "≈ 3% от поступлений (УСН, оценка)")
        case "OUR":
            return (roundMoney(max(0, p) * 0.10), "≈ 10% от денежного остатка (оценка)")
        case "TOO_CIT_GENERAL":
            return (roundMoney(max(0, p) * 0.20), "≈ 20% от денежного остатка (оценка)")
        case "MIXED_PERIOD":
            return (roundMoney(r * 0.03), "Смешанный период: нужен ответ дашборда с разбивкой по режимам")
        case "CUSTOM":
            return (roundMoney(r * 0.03), "Свой режим без ставки в ответе — ориентир 3% с поступлений")
        case "":
            return (roundMoney(r * 0.03), "≈ 3% от поступлений (оценка)")
        default:
            return (roundMoney(r * 0.03), "≈ 3% от поступлений (оценка)")
        }
    }

    private static func roundMoney(_ x: Double) -> Double {
        (x * 100).rounded() / 100
    }

    /// Компания из `/branches/`, совпадающая с первой должностью пользователя в `/team/` (как на бэкенде дашборда).
    static func pickPrimaryBranch(
        branches: [BranchCompany],
        team: TeamSnapshot?,
        userEmail: String?
    ) -> BranchCompany? {
        guard let first = branches.first else { return nil }
        guard let email = userEmail?.trimmingCharacters(in: .whitespaces),
              !email.isEmpty,
              let team
        else { return first }
        let needle = email.lowercased()
        for co in team.companies {
            for pos in co.positions {
                if pos.email.trimmingCharacters(in: .whitespaces).lowercased() == needle {
                    return branches.first(where: { $0.id == co.id }) ?? first
                }
            }
        }
        return first
    }
}
