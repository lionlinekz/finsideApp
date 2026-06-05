import SwiftUI
import UIKit

struct UncategorizedCategorizationView: View {
    let uploadId: Int?
    let iban: String?

    @Environment(\.dismiss) private var dismiss

    @State private var items: [UncategorizedTransaction] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var loadError: String?
    @State private var nextOffset: Int?
    @State private var totalCount = 0

    @State private var pickerTarget: UncategorizedTransaction?

    @State private var similarContext: SimilarApplyContext?
    @State private var toastMessage: String?

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("Загрузка транзакций…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError, items.isEmpty {
                ContentUnavailableView {
                    Label("Не удалось загрузить", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Повторить") { Task { await reload() } }
                        .buttonStyle(.bordered)
                }
            } else if items.isEmpty {
                ContentUnavailableView {
                    Label("Всё размечено", systemImage: "checkmark.circle")
                } description: {
                    Text("Неразмеченных операций из этой выписки не осталось.")
                } actions: {
                    Button("Готово") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                listContent
            }
        }
        .navigationTitle("Разметка категорий")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { dismiss() }
            }
        }
        .task {
            async let transactions: Void = reload()
            async let categories: Void = preloadCategories()
            _ = await (transactions, categories)
        }
        .refreshable {
            async let transactions: Void = reload()
            async let categories: Void = preloadCategories()
            _ = await (transactions, categories)
        }
        .sheet(item: $pickerTarget) { tx in
            NavigationStack {
                CategoryPickerSheet(
                    transaction: tx,
                    onCancel: { pickerTarget = nil },
                    onSave: { categoryId, subcategoryId in
                        Task {
                            await assignCategory(
                                transaction: tx,
                                categoryId: categoryId,
                                subcategoryId: subcategoryId
                            )
                        }
                    }
                )
            }
        }
        .sheet(item: $similarContext) { ctx in
            NavigationStack {
                SimilarTransactionsSheet(
                    context: ctx,
                    onDone: { message in
                        similarContext = nil
                        if let message {
                            toastMessage = message
                        }
                        Task { await reload() }
                    }
                )
            }
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { self.toastMessage = nil }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastMessage)
    }

    private var listContent: some View {
        List {
            if totalCount > 0 {
                Section {
                    Text("Осталось разметить: \(totalCount)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(items) { tx in
                    Button {
                        pickerTarget = tx
                    } label: {
                        transactionRow(tx)
                    }
                    .buttonStyle(.plain)
                }

                if nextOffset != nil {
                    HStack {
                        Spacer()
                        if isLoadingMore {
                            ProgressView()
                        } else {
                            Button("Загрузить ещё") {
                                Task { await loadMore() }
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func transactionRow(_ tx: UncategorizedTransaction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(tx.itemType?.title ?? tx.type)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(typeTint(tx).opacity(0.15), in: Capsule())
                    .foregroundStyle(typeTint(tx))

                Spacer()

                Text(formattedAmount(tx))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(typeTint(tx))
            }

            Text(tx.description.isEmpty ? "Без описания" : tx.description)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                Text(DashboardMoney.longDateLabel(tx.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !tx.bank.isEmpty {
                    Text(tx.bank.capitalized)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Label("Задать категорию", systemImage: "tag")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 4)
    }

    private func typeTint(_ tx: UncategorizedTransaction) -> Color {
        tx.itemType?.isIncome == true ? DashboardPalette.income : DashboardPalette.expense
    }

    private func formattedAmount(_ tx: UncategorizedTransaction) -> String {
        let prefix = tx.itemType?.isIncome == true ? "+" : "−"
        return prefix + DashboardMoney.formatTenge(tx.amountValue)
    }

    /// Прогреваем справочник категорий параллельно с транзакциями.
    private func preloadCategories() async {
        _ = try? await APIService.shared.categories()
    }

    private func reload() async {
        await MainActor.run {
            isLoading = true
            loadError = nil
            nextOffset = nil
            items = []
        }
        await fetch(offset: 0, append: false)
        await MainActor.run { isLoading = false }
    }

    private func loadMore() async {
        guard let offset = nextOffset, !isLoadingMore else { return }
        await MainActor.run { isLoadingMore = true }
        await fetch(offset: offset, append: true)
        await MainActor.run { isLoadingMore = false }
    }

    private func fetch(offset: Int, append: Bool) async {
        do {
            let page = try await APIService.shared.uncategorizedTransactions(
                uploadId: uploadId,
                iban: iban,
                offset: offset
            )
            await MainActor.run {
                totalCount = page.count
                if append {
                    items.append(contentsOf: page.results)
                } else {
                    items = page.results
                }
                nextOffset = page.nextOffset
                loadError = nil
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
            }
        }
    }

    private func assignCategory(
        transaction: UncategorizedTransaction,
        categoryId: Int,
        subcategoryId: Int?
    ) async {
        do {
            let response: AssignCategoryResponse
            if transaction.itemType?.isIncome == true {
                response = try await APIService.shared.assignIncomeCategory(
                    incomeId: transaction.id,
                    categoryId: categoryId,
                    subcategoryId: subcategoryId
                )
            } else {
                response = try await APIService.shared.assignPaymentCategory(
                    itemId: transaction.id,
                    categoryId: categoryId,
                    subcategoryId: subcategoryId
                )
            }

            let suggestions = try await APIService.shared.similarCategorySuggestions(
                itemType: response.itemType,
                itemId: response.itemId,
                uploadId: response.uploadId
            )

            await MainActor.run {
                pickerTarget = nil
                items.removeAll { $0.id == transaction.id && $0.type == transaction.type }
                if totalCount > 0 { totalCount -= 1 }

                let hasSimilar = suggestions.exact != nil
                    || !suggestions.substringCandidates.isEmpty

                if hasSimilar, let uploadId = response.uploadId {
                    similarContext = SimilarApplyContext(
                        itemType: response.itemType,
                        itemId: response.itemId,
                        uploadId: uploadId,
                        bank: response.bank,
                        categoryId: response.categoryId,
                        subcategoryId: response.subcategoryId,
                        suggestions: suggestions,
                        transactionDescription: transaction.description
                    )
                } else {
                    toastMessage = "Категория сохранена"
                    Task { await reload() }
                }
            }
        } catch {
            await MainActor.run {
                toastMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Category picker

private struct CategoryPickerSheet: View {
    let transaction: UncategorizedTransaction
    var onCancel: () -> Void
    var onSave: (Int, Int?) -> Void

    @State private var categories: [CategoryItem] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedCategoryId: Int?
    @State private var selectedSubcategoryId: Int?
    @State private var isSaving = false

    private var categoryType: CategoryType {
        if transaction.itemType?.isIncome == true || transaction.type == "income" {
            return .income
        }
        return .expense
    }

    private var selectedCategory: CategoryItem? {
        categories.first { $0.id == selectedCategoryId }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Загрузка категорий…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                formContent
            }
        }
        .navigationTitle("Категория")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") {
                    guard let categoryId = selectedCategoryId else { return }
                    isSaving = true
                    onSave(categoryId, selectedSubcategoryId)
                }
                .disabled(selectedCategoryId == nil || isSaving || isLoading)
            }
        }
        .task { await loadCategories() }
    }

    @ViewBuilder
    private var formContent: some View {
        Form {
            Section("Операция") {
                Text(transaction.description.isEmpty ? "Без описания" : transaction.description)
                    .font(.subheadline)
                Text(transaction.itemType?.title ?? transaction.type)
                    .foregroundStyle(.secondary)
            }

            Section("Категория") {
                if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Button("Повторить") { Task { await loadCategories() } }
                } else if categories.isEmpty {
                    Text("Нет категорий для \(categoryType.title.lowercased()) операций.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Категория", selection: $selectedCategoryId) {
                        Text("Выберите").tag(Optional<Int>.none)
                        ForEach(categories) { cat in
                            Text(cat.name).tag(Optional(cat.id))
                        }
                    }
                    .onChange(of: selectedCategoryId) { _, _ in
                        selectedSubcategoryId = nil
                    }
                }
            }

            if let cat = selectedCategory, !cat.subcategories.isEmpty {
                Section("Подкатегория") {
                    Picker("Подкатегория", selection: $selectedSubcategoryId) {
                        Text("Не выбрана").tag(Optional<Int>.none)
                        ForEach(cat.subcategories) { sub in
                            Text(sub.name).tag(Optional(sub.id))
                        }
                    }
                }
            }
        }
    }

    private func loadCategories() async {
        await MainActor.run {
            isLoading = true
            loadError = nil
        }
        do {
            var loaded = try await APIService.shared.categories(type: categoryType).categories
            if loaded.isEmpty {
                let all = try await APIService.shared.categories().categories
                loaded = all.filter { $0.type == categoryType.rawValue }
            }
            await MainActor.run {
                categories = loaded
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                categories = []
                isLoading = false
            }
        }
    }
}

// MARK: - Similar transactions

struct SimilarApplyContext: Identifiable {
    let id = UUID()
    let itemType: String
    let itemId: Int
    let uploadId: Int
    let bank: String
    let categoryId: Int
    let subcategoryId: Int?
    let suggestions: SimilarCategorySuggestions
    let transactionDescription: String
}

private struct SimilarTransactionsSheet: View {
    let context: SimilarApplyContext
    var onDone: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSubstring: String?
    @State private var customSubstring = ""
    @State private var isCustomPickerPresented = false
    @State private var isApplying = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text("Применить эту категорию к похожим операциям?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let exact = context.suggestions.exact, exact.countInUpload > 0 {
                Section("Точное совпадение") {
                    primaryActionButton(
                        title: "Применить к \(exact.countInUpload) в выписке",
                        subtitle: "Та же сумма и описание. Будет создано правило для будущих операций.",
                        systemImage: "equal.circle.fill"
                    ) {
                        await applyExact()
                    }
                }
            }

            if !context.suggestions.substringCandidates.isEmpty {
                Section {
                    Text("Выберите фрагмент описания для автоправила")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Текст из описания") {
                    ForEach(context.suggestions.substringCandidates) { candidate in
                        Button {
                            selectRecommendedCandidate(candidate.text)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: selectedSubstring == candidate.text ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedSubstring == candidate.text ? Color.accentColor : Color.secondary)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text("«\(candidate.text)»")
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        if candidate.isRecommended {
                                            Text("рекомендуем")
                                                .font(.caption2.weight(.medium))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.accentColor.opacity(0.15))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    Text("В выписке: \(candidate.countInUpload), по банку: \(candidate.countAllBank)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        isCustomPickerPresented = true
                    } label: {
                        Text("Выделить в описании")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("Похожие операции")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Пропустить") {
                    onDone(nil)
                    dismiss()
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let selectedSubstring, selectedSubstring.count >= 2 {
                substringApplyFooter
            }
        }
        .sheet(isPresented: $isCustomPickerPresented) {
            NavigationStack {
                CustomSubstringPickerSheet(
                    description: context.transactionDescription,
                    onConfirm: { text in
                        customSubstring = text
                        selectedSubstring = text
                    }
                )
            }
        }
        .disabled(isApplying)
        .onAppear {
            if selectedSubstring == nil,
               let recommended = context.suggestions.substringCandidates.first(where: { $0.isRecommended }) {
                selectRecommendedCandidate(recommended.text)
            }
        }
    }

    private func selectRecommendedCandidate(_ text: String) {
        selectedSubstring = text
        customSubstring = text
    }

    private var substringApplyFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selectedSubstring {
                Text("Выбрано: «\(selectedSubstring)»")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Button {
                Task {
                    isApplying = true
                    errorMessage = nil
                    let text = customSubstring.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard text.count >= 2 else {
                        isApplying = false
                        return
                    }
                    await applySubstring(text)
                    isApplying = false
                }
            } label: {
                HStack {
                    if isApplying {
                        ProgressView()
                            .tint(.white)
                    }
                    Label(
                        "Применить и создать правило",
                        systemImage: "wand.and.stars"
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isApplying)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    @ViewBuilder
    private func primaryActionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    isApplying = true
                    errorMessage = nil
                    await action()
                    isApplying = false
                }
            } label: {
                HStack {
                    if isApplying {
                        ProgressView()
                    }
                    Label(title, systemImage: systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.vertical, 4)
    }

    private func applyExact() async {
        do {
            let resp = try await APIService.shared.bulkApplyCategory(
                uploadId: context.uploadId,
                direction: context.itemType,
                referenceId: context.itemId,
                categoryId: context.categoryId,
                subcategoryId: context.subcategoryId
            )
            await MainActor.run {
                onDone("Категория применена к \(resp.updated) операциям")
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func applySubstring(_ text: String) async {
        do {
            let resp = try await APIService.shared.createTextAutocatRule(
                itemType: context.itemType,
                itemId: context.itemId,
                matchSubstring: text,
                categoryId: context.categoryId,
                subcategoryId: context.subcategoryId
            )
            await MainActor.run {
                onDone("Правило создано, обновлено \(resp.updated) операций")
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Custom substring picker

private struct CustomSubstringPickerSheet: View {
    let description: String
    var onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedText = ""

    private var displayDescription: String {
        description.isEmpty ? "Без описания" : description
    }

    var body: some View {
        List {
            Section {
                Text("Проведите по тексту, чтобы выделить фрагмент")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Описание операции") {
                DescriptionSubstringSelector(text: displayDescription, selectedText: $selectedText)
                    .frame(minHeight: 140)
                    .listRowInsets(EdgeInsets())
            }

            if selectedText.count >= 2 {
                Section("Правило") {
                    Text("«\(selectedText)»")
                        .font(.body.weight(.medium))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Свой фрагмент")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") {
                    onConfirm(selectedText)
                    dismiss()
                }
                .disabled(selectedText.count < 2)
            }
        }
    }
}

private struct DescriptionSubstringSelector: UIViewRepresentable {
    let text: String
    @Binding var selectedText: String

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedText: $selectedText)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.text = text
        textView.dataDetectorTypes = []
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var selectedText: String

        init(selectedText: Binding<String>) {
            _selectedText = selectedText
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let range = textView.selectedTextRange, !range.isEmpty else {
                selectedText = ""
                return
            }
            let raw = textView.text(in: range) ?? ""
            selectedText = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

#Preview {
    NavigationStack {
        UncategorizedCategorizationView(uploadId: 1, iban: nil)
    }
}
