import SwiftUI

struct CategoriesView: View {
    @State private var selectedType: CategoryType = .expense
    @State private var categories: [CategoryItem] = []
    @State private var typeOptions: [CategoryTypeOption] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var showAddCategory = false
    @State private var addSubcategoryTarget: CategoryItem?

    var body: some View {
        Group {
            if isLoading && categories.isEmpty {
                ProgressView("Загрузка…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError, filteredCategories.isEmpty {
                ContentUnavailableView {
                    Label("Не удалось загрузить", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(err)
                } actions: {
                    Button("Повторить") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            } else if filteredCategories.isEmpty {
                ContentUnavailableView {
                    Label("Нет категорий", systemImage: "folder")
                } description: {
                    Text("Добавьте категорию для \(selectedType.title.lowercased()) операций.")
                } actions: {
                    Button("Добавить категорию") { showAddCategory = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                categoriesList
            }
        }
        .navigationTitle("Категории")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddCategory = true } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    CategoryAutomationRulesView()
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .accessibilityLabel("Правила автоматизации")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            typePicker
        }
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: selectedType) { _, _ in
            Task { await load() }
        }
        .sheet(isPresented: $showAddCategory) {
            NavigationStack {
                AddCategorySheet(defaultType: selectedType) {
                    showAddCategory = false
                    Task { await load() }
                }
            }
        }
        .sheet(item: $addSubcategoryTarget) { category in
            NavigationStack {
                AddSubcategorySheet(category: category) {
                    addSubcategoryTarget = nil
                    Task { await load() }
                }
            }
        }
    }

    private var filteredCategories: [CategoryItem] {
        categories.filter { $0.type == selectedType.rawValue }
    }

    private var typePicker: some View {
        Picker("Тип", selection: $selectedType) {
            ForEach(CategoryType.allCases) { type in
                Text(type.title).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var categoriesList: some View {
        List {
            ForEach(filteredCategories) { category in
                Section {
                    if category.subcategories.isEmpty {
                        Text("Нет подкатегорий")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(category.subcategories) { sub in
                            subcategoryRow(sub)
                        }
                    }

                    Button {
                        addSubcategoryTarget = category
                    } label: {
                        Label("Добавить подкатегорию", systemImage: "plus.circle")
                            .font(.subheadline)
                    }
                } header: {
                    Text(category.name)
                        .font(.headline)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func subcategoryRow(_ sub: SubcategoryItem) -> some View {
        HStack(spacing: 10) {
            Text(sub.name)
                .font(.body)

            if sub.isTransfer {
                Text("перевод")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 0)

            if sub.hasAutomation {
                Image(systemName: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Есть автоматизация")
            }
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            loadError = nil
        }
        do {
            let response = try await APIService.shared.categories(type: selectedType)
            await MainActor.run {
                categories = response.categories
                if !response.types.isEmpty {
                    typeOptions = response.types
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - Add Category Sheet

private struct AddCategorySheet: View {
    let defaultType: CategoryType
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedType: CategoryType
    @State private var isSubmitting = false
    @State private var formError: String?

    init(defaultType: CategoryType, onFinished: @escaping () -> Void) {
        self.defaultType = defaultType
        self.onFinished = onFinished
        _selectedType = State(initialValue: defaultType)
    }

    var body: some View {
        Form {
            Section("Категория") {
                TextField("Наименование", text: $name)
                    .textInputAutocapitalization(.sentences)

                Picker("Тип", selection: $selectedType) {
                    ForEach(CategoryType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
            }

            if let formError {
                Section {
                    Label(formError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Новая категория")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") {
                    dismiss()
                    onFinished()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Добавить") { Task { await submit() } }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
    }

    private func submit() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await MainActor.run {
            isSubmitting = true
            formError = nil
        }
        do {
            _ = try await APIService.shared.addCategory(name: trimmed, type: selectedType)
            await MainActor.run {
                isSubmitting = false
                dismiss()
                onFinished()
            }
        } catch {
            await MainActor.run {
                formError = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - Add Subcategory Sheet

private struct AddSubcategorySheet: View {
    let category: CategoryItem
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var isSubmitting = false
    @State private var formError: String?

    var body: some View {
        Form {
            Section("Категория") {
                Text(category.name)
                    .foregroundStyle(.secondary)
            }

            Section("Подкатегория") {
                TextField("Наименование", text: $name)
                    .textInputAutocapitalization(.sentences)
            }

            if let formError {
                Section {
                    Label(formError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Новая подкатегория")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") {
                    dismiss()
                    onFinished()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Добавить") { Task { await submit() } }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
    }

    private func submit() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await MainActor.run {
            isSubmitting = true
            formError = nil
        }
        do {
            _ = try await APIService.shared.addSubcategory(categoryId: category.id, name: trimmed)
            await MainActor.run {
                isSubmitting = false
                dismiss()
                onFinished()
            }
        } catch {
            await MainActor.run {
                formError = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        CategoriesView()
    }
}
