import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private enum ExpenseMoneySource: String, CaseIterable, Identifiable {
    case personal
    case business

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: return "Личные деньги"
        case .business: return "Деньги бизнеса"
        }
    }

    var isPersonalMoney: Bool {
        self == .personal
    }
}

private struct ExpenseBankOption: Identifiable, Hashable {
    let code: String
    let title: String
    var id: String { code }
}

private let expenseBankOptions: [ExpenseBankOption] = [
    ExpenseBankOption(code: "kaspi", title: "Kaspi"),
    ExpenseBankOption(code: "halyk", title: "Halyk"),
    ExpenseBankOption(code: "forte", title: "Forte"),
    ExpenseBankOption(code: "altyn", title: "Altyn"),
    ExpenseBankOption(code: "bcc", title: "CenterCredit"),
    ExpenseBankOption(code: "eurasian", title: "Евразийский"),
    ExpenseBankOption(code: "jusan", title: "Jusan"),
    ExpenseBankOption(code: "otbasy", title: "Отбасы"),
]

/// Ручное добавление расхода с главного дашборда.
struct AddExpenseSheet: View {
    var defaultDate: Date = .now
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var amountDigits = ""
    @State private var descriptionText = ""
    @State private var expenseDate: Date
    @State private var moneySource: ExpenseMoneySource = .personal
    @State private var selectedBankCode: String?
    @State private var categories: [CategoryItem] = []
    @State private var selectedCategoryId: Int?
    @State private var selectedSubcategoryId: Int?
    @State private var isLoadingCategories = true
    @State private var isSubmitting = false
    @State private var formError: String?
    @State private var showSuccess = false
    @State private var successScale: CGFloat = 0.6

    init(defaultDate: Date = .now, onSaved: @escaping () -> Void) {
        self.defaultDate = defaultDate
        self.onSaved = onSaved
        _expenseDate = State(initialValue: defaultDate)
    }

    private static let amountFont = Font.system(size: 40, weight: .bold, design: .rounded)

    private var parsedAmount: Double? {
        guard !amountDigits.isEmpty, let value = Double(amountDigits), value > 0 else { return nil }
        return value
    }

    private var savedAmountLabel: String {
        guard let amount = parsedAmount else { return "0 ₸" }
        return DashboardMoney.formatTenge(amount)
    }

    private var expenseCategories: [CategoryItem] {
        categories.filter { $0.categoryType == .expense }
    }

    private var subcategoriesForSelection: [SubcategoryItem] {
        guard let categoryId = selectedCategoryId,
              let category = expenseCategories.first(where: { $0.id == categoryId })
        else { return [] }
        return category.subcategories
    }

    private var canSubmit: Bool {
        parsedAmount != nil && !isSubmitting && !showSuccess
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Сумма")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Spacer(minLength: 0)
                                #if canImport(UIKit)
                                GroupedAmountTextField(digits: $amountDigits, focusOnAppear: true)
                                    .frame(minWidth: 80)
                                #else
                                TextField("0", text: $amountDigits)
                                    .font(Self.amountFont)
                                    .multilineTextAlignment(.trailing)
                                    .keyboardType(.numberPad)
                                #endif
                                Text("₸")
                                    .font(Self.amountFont)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                    }

                    Section("Детали") {
                        TextField("Описание", text: $descriptionText, axis: .vertical)
                            .lineLimit(1...3)
                        DatePicker("Дата", selection: $expenseDate, displayedComponents: [.date, .hourAndMinute])
                    }

                    Section("Источник денег") {
                        Picker("Источник", selection: $moneySource) {
                            ForEach(ExpenseMoneySource.allCases) { source in
                                Text(source.title).tag(source)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }

                    Section("Категория") {
                        if isLoadingCategories {
                            HStack {
                                ProgressView()
                                Text("Загрузка категорий…")
                                    .foregroundStyle(.secondary)
                            }
                        } else if expenseCategories.isEmpty {
                            Text("Нет расходных категорий. Добавьте их в настройках.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Категория", selection: $selectedCategoryId) {
                                Text("Не выбрана").tag(Optional<Int>.none)
                                ForEach(expenseCategories) { cat in
                                    Text(cat.name).tag(Optional(cat.id))
                                }
                            }
                            .onChange(of: selectedCategoryId) { _, _ in
                                selectedSubcategoryId = nil
                            }

                            if !subcategoriesForSelection.isEmpty {
                                Picker("Подкатегория", selection: $selectedSubcategoryId) {
                                    Text("Не выбрана").tag(Optional<Int>.none)
                                    ForEach(subcategoriesForSelection) { sub in
                                        Text(sub.name).tag(Optional(sub.id))
                                    }
                                }
                            }
                        }
                    }

                    Section("Банк") {
                        Picker("Банк", selection: $selectedBankCode) {
                            Text("Не указан").tag(Optional<String>.none)
                            ForEach(expenseBankOptions) { bank in
                                Text(bank.title).tag(Optional(bank.code))
                            }
                        }
                    }

                    if let formError {
                        Section {
                            Label(formError, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }
                    }
                }
                .formStyle(.grouped)
                .disabled(showSuccess)

                if showSuccess {
                    successOverlay
                }
            }
            .navigationTitle("Новый расход")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .disabled(isSubmitting || showSuccess)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Добавить") {
                            Task { await submit() }
                        }
                        .fontWeight(.medium)
                        .tint(Color(.secondaryLabel))
                        .disabled(!canSubmit)
                    }
                }
            }
            .task { await loadCategories() }
        }
    }

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(DashboardPalette.income)
                    .scaleEffect(successScale)
                Text("Расход добавлен")
                    .font(.title3.weight(.semibold))
                Text(savedAmountLabel)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(32)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }

    private func loadCategories() async {
        await MainActor.run { isLoadingCategories = true }
        do {
            let response = try await APIService.shared.categories(type: .expense)
            await MainActor.run {
                categories = response.categories
                isLoadingCategories = false
            }
        } catch {
            await MainActor.run {
                formError = error.localizedDescription
                isLoadingCategories = false
            }
        }
    }

    private func submit() async {
        guard let amount = parsedAmount else {
            await MainActor.run {
                formError = "Укажите сумму больше нуля"
                DashboardHaptics.warning()
            }
            return
        }

        await MainActor.run {
            isSubmitting = true
            formError = nil
        }

        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            _ = try await APIService.shared.addExpense(
                amount: amount,
                description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                date: expenseDate,
                categoryId: selectedSubcategoryId == nil ? selectedCategoryId : nil,
                subcategoryId: selectedSubcategoryId,
                isPersonalMoney: moneySource.isPersonalMoney,
                paymentBank: selectedBankCode
            )

            await MainActor.run {
                isSubmitting = false
                DashboardHaptics.success()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                    showSuccess = true
                    successScale = 1
                }
            }

            try? await Task.sleep(nanoseconds: 850_000_000)

            await MainActor.run {
                NotificationCenter.default.post(name: .finsideLedgerDidChange, object: nil)
                onSaved()
                dismiss()
            }
        } catch {
            await MainActor.run {
                isSubmitting = false
                formError = error.localizedDescription
                DashboardHaptics.warning()
            }
        }
    }
}

// MARK: - Amount field (live thousand separators)

#if canImport(UIKit)
private func formatGroupedAmountDigits(_ digits: String) -> String {
    let d = String(digits.filter(\.isNumber))
    guard !d.isEmpty else { return "" }
    var parts: [String] = []
    var idx = d.endIndex
    while idx > d.startIndex {
        let start = d.index(idx, offsetBy: -3, limitedBy: d.startIndex) ?? d.startIndex
        parts.insert(String(d[start..<idx]), at: 0)
        idx = start
    }
    return parts.joined(separator: " ")
}

private struct GroupedAmountTextField: UIViewRepresentable {
    @Binding var digits: String
    var focusOnAppear: Bool

    private static var amountUIFont: UIFont {
        let base = UIFont.systemFont(ofSize: 40, weight: .bold)
        if let rounded = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: rounded, size: 40)
        }
        return base
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(digits: $digits)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = .numberPad
        field.textAlignment = .right
        field.font = Self.amountUIFont
        field.placeholder = "0"
        field.delegate = context.coordinator
        field.text = formatGroupedAmountDigits(digits)
        field.borderStyle = .none
        field.backgroundColor = .clear
        if focusOnAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                field.becomeFirstResponder()
            }
        }
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        let formatted = formatGroupedAmountDigits(digits)
        if uiView.text != formatted {
            uiView.text = formatted
            moveCaretToEnd(uiView)
        }
    }

    private func moveCaretToEnd(_ field: UITextField) {
        let end = field.endOfDocument
        field.selectedTextRange = field.textRange(from: end, to: end)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var digits: String

        init(digits: Binding<String>) {
            _digits = digits
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let current = textField.text ?? ""
            guard let textRange = Range(range, in: current) else { return false }
            let proposed = current.replacingCharacters(in: textRange, with: string)
            let newDigits = String(proposed.filter(\.isNumber))
            digits = newDigits
            textField.text = formatGroupedAmountDigits(newDigits)
            let end = textField.endOfDocument
            textField.selectedTextRange = textField.textRange(from: end, to: end)
            return false
        }
    }
}
#endif

#Preview {
    AddExpenseSheet(onSaved: {})
}
