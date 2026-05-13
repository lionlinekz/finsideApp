import SwiftUI

enum HomeLedgerRoute: Hashable {
    case allIncome(title: String)
    case incomeByMethod(methodLabel: String)
    case incomeByBank(bankName: String)
    case incomeCashPersonal
    case incomeCashBusiness
    case salesByManager(profileId: Int, title: String)
    case salesByPoint(pointId: Int, title: String)
    case expenseCategory(categoryId: Int, title: String)
    /// `isPersonal == true` — с своих счетов; `false` — со счетов ИП.
    case expenseByAccountSource(isPersonal: Bool)
}

struct LedgerListView: View {
    let route: HomeLedgerRoute
    let period: String
    let date: String?

    @State private var lines: [LedgerLine] = []
    @State private var totalCount = 0
    @State private var nextOffset: Int?
    @State private var loading = true
    @State private var loadingMore = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if loading && lines.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, lines.isEmpty {
                ContentUnavailableView(
                    "Не удалось загрузить",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                List {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        ledgerRow(line)
                            .onAppear {
                                guard index == lines.count - 1, nextOffset != nil, !loadingMore else { return }
                                Task { await loadMoreIfNeeded() }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var title: String {
        switch route {
        case .allIncome(let t): return t
        case .incomeByMethod(let label): return label
        case .incomeByBank(let bank): return bank
        case .incomeCashPersonal: return "Наличные · личные"
        case .incomeCashBusiness: return "Наличные · бизнес"
        case .salesByManager(_, let t): return t
        case .salesByPoint(_, let t): return t
        case .expenseCategory(_, let t): return t
        case .expenseByAccountSource(let isPersonal):
            return isPersonal ? "С своих счетов" : "Со счетов ИП"
        }
    }

    @ViewBuilder
    private func ledgerRow(_ line: LedgerLine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(DashboardMoney.longDateLabel(line.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(DashboardMoney.formatTenge(line.amount))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            if !line.description.isEmpty {
                Text(line.description)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            let meta = [line.paymentMethod, line.paymentBank].filter { !$0.isEmpty }.joined(separator: " · ")
            if !meta.isEmpty {
                Text(meta)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func reload() async {
        loading = true
        errorMessage = nil
        nextOffset = nil
        lines = []
        await fetch(offset: 0, append: false)
        loading = false
    }

    private func loadMoreIfNeeded() async {
        guard let off = nextOffset, !loadingMore else { return }
        loadingMore = true
        await fetch(offset: off, append: true)
        loadingMore = false
    }

    private func fetch(offset: Int, append: Bool) async {
        do {
            let page: LedgerLinesResponse
            switch route {
            case .allIncome:
                page = try await APIService.shared.dashboardIncomeLines(
                    period: period,
                    date: date,
                    offset: offset,
                    limit: 50
                )
            case .incomeByMethod(let methodLabel):
                page = try await APIService.shared.dashboardIncomeLines(
                    period: period,
                    date: date,
                    offset: offset,
                    limit: 50,
                    paymentMethod: methodLabel,
                    paymentBank: nil,
                    cashScope: nil
                )
            case .incomeByBank(let bankName):
                page = try await APIService.shared.dashboardIncomeLines(
                    period: period,
                    date: date,
                    offset: offset,
                    limit: 50,
                    paymentMethod: nil,
                    paymentBank: bankName,
                    cashScope: nil
                )
            case .incomeCashPersonal:
                page = try await APIService.shared.dashboardIncomeLines(
                    period: period,
                    date: date,
                    offset: offset,
                    limit: 50,
                    paymentMethod: nil,
                    paymentBank: nil,
                    cashScope: "personal"
                )
            case .incomeCashBusiness:
                page = try await APIService.shared.dashboardIncomeLines(
                    period: period,
                    date: date,
                    offset: offset,
                    limit: 50,
                    paymentMethod: nil,
                    paymentBank: nil,
                    cashScope: "business"
                )
            case .salesByManager(let profileId, _):
                page = try await APIService.shared.dashboardSalesLines(
                    period: period,
                    date: date,
                    profileId: profileId,
                    pointId: nil,
                    offset: offset,
                    limit: 50
                )
            case .salesByPoint(let pointId, _):
                page = try await APIService.shared.dashboardSalesLines(
                    period: period,
                    date: date,
                    profileId: nil,
                    pointId: pointId,
                    offset: offset,
                    limit: 50
                )
            case .expenseCategory(let categoryId, _):
                page = try await APIService.shared.dashboardExpenseLines(
                    period: period,
                    date: date,
                    categoryId: categoryId,
                    personalMoney: nil,
                    offset: offset,
                    limit: 50
                )
            case .expenseByAccountSource(let isPersonal):
                page = try await APIService.shared.dashboardExpenseLines(
                    period: period,
                    date: date,
                    categoryId: nil,
                    personalMoney: isPersonal,
                    offset: offset,
                    limit: 50
                )
            }
            totalCount = page.count
            if append {
                lines.append(contentsOf: page.results)
            } else {
                lines = page.results
            }
            nextOffset = page.nextOffset
        } catch {
            if !append { errorMessage = error.localizedDescription }
        }
    }
}
