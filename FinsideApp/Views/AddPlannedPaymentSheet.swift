import SwiftUI

/// Тип платежа — быстрый выбор поверх уже существующих категорий/подкатегорий
/// (а не отдельное поле): так закрытый платёж сразу попадает в те же отчёты,
/// что и остальные расходы. «Другое» открывает обычный выбор категории.
private struct QuickPlannedPaymentType: Identifiable {
    let id: String
    let label: String
    let icon: String
    /// Код подкатегории (`Subcategory.code` на бэкенде), по которому ищем
    /// готовую категорию/подкатегорию в уже загруженном списке.
    let subcategoryCode: String
}

private let quickPlannedPaymentTypes: [QuickPlannedPaymentType] = [
    QuickPlannedPaymentType(id: "utilities", label: "Коммунальные услуги", icon: "bolt.fill", subcategoryCode: "UTILITIES"),
    QuickPlannedPaymentType(id: "loan", label: "Кредит", icon: "banknote", subcategoryCode: "LOAN_PAYMENT"),
    QuickPlannedPaymentType(id: "mortgage", label: "Ипотека", icon: "house.fill", subcategoryCode: "MORTGAGE_PAYMENT"),
    QuickPlannedPaymentType(id: "rent", label: "Аренда", icon: "building.2.fill", subcategoryCode: "RENT"),
]
private let otherPlannedPaymentTypeId = "other"

/// Создание планового платежа: разовый или повторяющийся (только
/// ежемесячно — см. бэкенд), с обязательной датой окончания для
/// повторяющихся, и типом поверх реальных категорий/подкатегорий.
struct AddPlannedPaymentSheet: View {
    var initialDate: Date = .now
    var onCreated: (CalendarEvent) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var descriptionText = ""
    @State private var date: Date
    @State private var isRecurring = false
    @State private var endDate: Date

    @State private var categories: [CategoryItem] = []
    @State private var isLoadingCategories = true
    @State private var selectedTypeId: String?
    @State private var selectedCategoryId: Int?
    @State private var selectedSubcategoryId: Int?

    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let maxRecurrenceYears = 20
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(initialDate: Date = .now, onCreated: @escaping (CalendarEvent) -> Void) {
        self.initialDate = initialDate
        self.onCreated = onCreated
        let start = Calendar.current.startOfDay(for: max(initialDate, Date()))
        _date = State(initialValue: start)
        _endDate = State(initialValue: Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start)
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

    private var parsedAmount: Double? {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private var maxEndDate: Date {
        Calendar.current.date(byAdding: .year, value: Self.maxRecurrenceYears, to: date) ?? date
    }

    private var canSubmit: Bool {
        guard parsedAmount != nil, !isSaving else { return false }
        if isRecurring && endDate <= date { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form { Group {
                Section("Сумма и дата") {
                    HStack {
                        Text("Сумма")
                        Spacer()
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("₸").foregroundStyle(.secondary)
                    }
                    DatePicker("Дата", selection: $date, in: Date()..., displayedComponents: .date)
                    TextField("Описание (необязательно)", text: $descriptionText, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("Повтор") {
                    Toggle("Повторяющийся платёж", isOn: $isRecurring.animation())
                    if isRecurring {
                        DatePicker(
                            "Дата окончания",
                            selection: $endDate,
                            in: date...maxEndDate,
                            displayedComponents: .date
                        )
                        Text("Повторяется ежемесячно, в это же число, до даты окончания.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Тип платежа") {
                    if isLoadingCategories {
                        HStack {
                            ProgressView()
                            Text("Загрузка категорий…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        typePicker
                        if selectedTypeId == otherPlannedPaymentTypeId {
                            otherCategoryPicker
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }.appListRowBackground() }.appListBackground()
            .navigationTitle("Плановый платёж")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Создать")
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
        }.appScreenBackground()
        .interactiveDismissDisabled(isSaving)
        .task { await loadCategories() }
        .onChange(of: date) { _, newDate in
            if endDate <= newDate {
                endDate = Calendar.current.date(byAdding: .month, value: 1, to: newDate) ?? newDate
            }
        }
    }

    // MARK: - Тип платежа

    private var typePicker: some View {
        Picker("Тип", selection: $selectedTypeId) {
            Text("Выберите тип").tag(Optional<String>.none)
            ForEach(quickPlannedPaymentTypes) { type in
                Label(type.label, systemImage: type.icon).tag(Optional(type.id))
            }
            Label("Другое", systemImage: "square.grid.2x2").tag(Optional(otherPlannedPaymentTypeId))
        }
        .onChange(of: selectedTypeId) { _, newValue in
            applyQuickType(newValue)
        }
    }

    private var otherCategoryPicker: some View {
        Group {
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

    /// Находит категорию/подкатегорию по коду быстрого типа в уже
    /// загруженном списке. Если код не нашёлся (у тенанта почему-то нет
    /// такой подкатегории) — просто не проставляем, платёж создастся без категории.
    private func applyQuickType(_ typeId: String?) {
        guard let typeId, typeId != otherPlannedPaymentTypeId,
              let quickType = quickPlannedPaymentTypes.first(where: { $0.id == typeId })
        else {
            if typeId != otherPlannedPaymentTypeId {
                selectedCategoryId = nil
                selectedSubcategoryId = nil
            }
            return
        }
        for category in expenseCategories {
            if let sub = category.subcategories.first(where: { $0.code == quickType.subcategoryCode }) {
                selectedCategoryId = category.id
                selectedSubcategoryId = sub.id
                return
            }
        }
    }

    // MARK: - Действия

    private func loadCategories() async {
        isLoadingCategories = true
        do {
            categories = try await APIService.shared.categories(type: .expense).categories
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingCategories = false
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        errorMessage = nil
        isSaving = true
        let amountString = String(format: "%.2f", amount)
        let dateString = Self.dateFormatter.string(from: date)
        let endDateString = isRecurring ? Self.dateFormatter.string(from: endDate) : nil
        Task {
            do {
                let created = try await APIService.shared.addPlannedPayment(
                    amount: amountString,
                    date: dateString,
                    description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
                    categoryId: selectedCategoryId,
                    subcategoryId: selectedSubcategoryId,
                    isRecurring: isRecurring,
                    endDate: endDateString
                )
                onCreated(created)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

#Preview {
    AddPlannedPaymentSheet(onCreated: { _ in })
}
