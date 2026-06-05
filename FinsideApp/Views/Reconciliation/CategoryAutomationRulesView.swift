import SwiftUI

private struct EditableAutomationRule: Identifiable {
    let rule: AutomationRuleItem
    var id: String { "\(rule.kind)-\(rule.id)" }
}

struct CategoryAutomationRulesView: View {
    @State private var rules: [AutomationRuleItem] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var editingRule: EditableAutomationRule?
    @State private var rulePendingDelete: AutomationRuleItem?

    var body: some View {
        Group {
            if isLoading && rules.isEmpty {
                ProgressView("Загрузка правил…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError, rules.isEmpty {
                ContentUnavailableView {
                    Label("Не удалось загрузить", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Повторить") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            } else if rules.isEmpty {
                ContentUnavailableView {
                    Label("Нет правил", systemImage: "wand.and.stars")
                } description: {
                    Text("Правила создаются при разметке категорий — когда вы применяете категорию к похожим операциям.")
                }
            } else {
                rulesList
            }
        }
        .navigationTitle("Правила категорий")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editingRule) { wrapper in
            NavigationStack {
                EditAutomationRuleSheet(rule: wrapper.rule) {
                    editingRule = nil
                    Task { await load() }
                }
            }
        }
        .confirmationDialog(
            "Удалить правило?",
            isPresented: Binding(
                get: { rulePendingDelete != nil },
                set: { if !$0 { rulePendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let rule = rulePendingDelete {
                    Task { await deleteRule(rule) }
                }
            }
            Button("Отмена", role: .cancel) { rulePendingDelete = nil }
        } message: {
            if let rule = rulePendingDelete {
                Text(rule.match)
            }
        }
    }

    private var rulesList: some View {
        List {
            ForEach(rules) { rule in
                Button {
                    editingRule = EditableAutomationRule(rule: rule)
                } label: {
                    ruleRow(rule)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        rulePendingDelete = rule
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func ruleRow(_ rule: AutomationRuleItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(rule.kindTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                Text(rule.directionTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(rule.bank.capitalized)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(rule.match)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(3)

            Text("\(rule.categoryName)\(rule.subcategoryName.map { " → \($0)" } ?? "")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            loadError = nil
        }
        do {
            let response = try await APIService.shared.automationRules()
            await MainActor.run {
                rules = response.rules
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func deleteRule(_ rule: AutomationRuleItem) async {
        do {
            try await APIService.shared.deleteAutomationRule(kind: rule.kind, id: rule.id)
            await MainActor.run {
                rules.removeAll { $0.id == rule.id && $0.kind == rule.kind }
                rulePendingDelete = nil
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                rulePendingDelete = nil
            }
        }
    }
}

private struct EditAutomationRuleSheet: View {
    let rule: AutomationRuleItem
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var matchDescription: String
    @State private var matchAmount: String
    @State private var matchSubstring: String
    @State private var categories: [CategoryItem] = []
    @State private var selectedCategoryId: Int?
    @State private var selectedSubcategoryId: Int?
    @State private var isSaving = false
    @State private var formError: String?

    init(rule: AutomationRuleItem, onFinished: @escaping () -> Void) {
        self.rule = rule
        self.onFinished = onFinished
        _matchDescription = State(initialValue: rule.matchDescription ?? "")
        _matchAmount = State(initialValue: rule.matchAmount ?? "")
        _matchSubstring = State(initialValue: rule.matchSubstring ?? "")
        _selectedCategoryId = State(initialValue: rule.categoryId)
        _selectedSubcategoryId = State(initialValue: rule.subcategoryId)
    }

    private var selectedCategory: CategoryItem? {
        categories.first { $0.id == selectedCategoryId }
    }

    private var wantedType: CategoryType {
        rule.direction == "income" ? .income : .expense
    }

    var body: some View {
        Form {
            Section("Правило") {
                Text(rule.kindTitle)
                Text(rule.directionTitle)
                Text(rule.bank.capitalized)
                    .foregroundStyle(.secondary)
            }

            if rule.kind == "exact" {
                Section("Совпадение") {
                    TextField("Описание", text: $matchDescription)
                    TextField("Сумма", text: $matchAmount)
                        .keyboardType(.decimalPad)
                }
            } else {
                Section("Подстрока") {
                    TextField("Текст в описании", text: $matchSubstring)
                }
            }

            Section("Категория") {
                Picker("Категория", selection: $selectedCategoryId) {
                    Text("Выберите").tag(Optional<Int>.none)
                    ForEach(categories) { cat in
                        Text(cat.name).tag(Optional(cat.id))
                    }
                }
                .onChange(of: selectedCategoryId) { _, _ in
                    selectedSubcategoryId = nil
                }

                if let cat = selectedCategory, !cat.subcategories.isEmpty {
                    Picker("Подкатегория", selection: $selectedSubcategoryId) {
                        Text("Не выбрана").tag(Optional<Int>.none)
                        ForEach(cat.subcategories) { sub in
                            Text(sub.name).tag(Optional(sub.id))
                        }
                    }
                }
            }

            if let formError {
                Section {
                    Text(formError)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Правило")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") {
                    dismiss()
                    onFinished()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { Task { await save() } }
                    .disabled(isSaving || selectedCategoryId == nil)
            }
        }
        .task { await loadCategories() }
    }

    private func loadCategories() async {
        do {
            let response = try await APIService.shared.categories(type: wantedType)
            await MainActor.run {
                categories = response.categories
            }
        } catch {
            await MainActor.run {
                formError = error.localizedDescription
            }
        }
    }

    private func save() async {
        guard let categoryId = selectedCategoryId else { return }
        await MainActor.run {
            isSaving = true
            formError = nil
        }
        do {
            _ = try await APIService.shared.updateAutomationRule(
                kind: rule.kind,
                id: rule.id,
                matchDescription: rule.kind == "exact" ? matchDescription : nil,
                matchAmount: rule.kind == "exact" ? matchAmount : nil,
                matchSubstring: rule.kind == "substring" ? matchSubstring : nil,
                categoryId: categoryId,
                subcategoryId: selectedSubcategoryId
            )
            await MainActor.run {
                isSaving = false
                dismiss()
                onFinished()
            }
        } catch {
            await MainActor.run {
                formError = error.localizedDescription
                isSaving = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        CategoryAutomationRulesView()
    }
}
