import SwiftUI

struct CompanySettingsView: View {
    @State private var companies: [BranchCompany] = []
    @State private var selectedCompanyId: Int?
    @State private var bin = ""
    @State private var taxMode = ""
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var saveError: String?

    private var selectedCompany: BranchCompany? {
        guard let id = selectedCompanyId else { return nil }
        return companies.first { $0.id == id }
    }

    private var canSave: Bool {
        let binOk = bin.trimmingCharacters(in: .whitespaces).count == 12
        return binOk && selectedCompany != nil
    }

    var body: some View {
        Group {
            if isLoading && companies.isEmpty {
                ProgressView("Загрузка…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError, companies.isEmpty {
                ContentUnavailableView {
                    Label("Не удалось загрузить", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(err)
                } actions: {
                    Button("Повторить") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if companies.isEmpty {
                ContentUnavailableView {
                    Label("Нет компании", systemImage: "building.2")
                } description: {
                    Text("Добавьте компанию в разделе «Филиалы».")
                }
            } else {
                formContent
            }
        }
        .navigationTitle("Компания")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: selectedCompanyId) { _, _ in
            syncFormFromSelection()
        }
    }

    private var formContent: some View {
        Form {
            if companies.count > 1 {
                Section("Компания") {
                    Picker("Юрлицо", selection: $selectedCompanyId) {
                        ForEach(companies, id: \.id) { c in
                            Text(c.name).tag(Optional(c.id))
                        }
                    }
                }
            }

            if let c = selectedCompany {
                Section {
                    LabeledContent("Наименование", value: c.name)
                    LabeledContent("Тип", value: c.companyTypeLabel)
                }

                Section("Реквизиты") {
                    TextField("ИИН/БИН (12 цифр)", text: $bin)
                        .keyboardType(.numberPad)
                }

                Section("Налоговый режим") {
                    Picker("Режим", selection: $taxMode) {
                        Text("Не указан").tag("")
                        if c.companyType != "TOO" {
                            Text("Патент (1%)").tag("PATENT")
                        }
                        Text("Упрощённый (3%)").tag("USN")
                        Text("Общий (10%)").tag("OUR")
                    }
                }

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Сохранить")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
        .onAppear {
            syncFormFromSelection()
        }
    }

    private func syncFormFromSelection() {
        guard let c = selectedCompany else { return }
        bin = c.bin
        taxMode = c.taxMode
        if c.companyType == "TOO", taxMode == "PATENT" {
            taxMode = ""
        }
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            loadError = nil
        }
        do {
            let list = try await APIService.shared.branches()
            await MainActor.run {
                companies = list
                if selectedCompanyId == nil || !list.contains(where: { $0.id == selectedCompanyId }) {
                    selectedCompanyId = list.first?.id
                }
                isLoading = false
                syncFormFromSelection()
            }
        } catch {
            let msg = error.localizedDescription
            await MainActor.run {
                loadError = msg
                isLoading = false
            }
        }
    }

    @MainActor
    private func save() async {
        guard let c = selectedCompany else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let binDigits = bin.trimmingCharacters(in: .whitespaces)
        guard binDigits.count == 12 else {
            saveError = "ИИН/БИН должен содержать 12 цифр"
            return
        }

        do {
            _ = try await APIService.shared.editCompany(
                id: c.id,
                name: c.name,
                direction: c.direction,
                taxMode: taxMode,
                bin: binDigits
            )
            await load()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        CompanySettingsView()
    }
}
