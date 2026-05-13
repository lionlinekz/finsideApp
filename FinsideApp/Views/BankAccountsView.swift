import SwiftUI

struct BankAccountsView: View {
    @State private var accounts: [BankAccountItem] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var showAdd = false
    @State private var deleteTarget: BankAccountItem?

    var body: some View {
        Group {
            if isLoading && accounts.isEmpty {
                ProgressView("Загрузка…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError, accounts.isEmpty {
                ContentUnavailableView {
                    Label("Не удалось загрузить", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(err)
                } actions: {
                    Button("Повторить") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            } else if accounts.isEmpty {
                ContentUnavailableView {
                    Label("Нет банковских счетов", systemImage: "building.columns")
                } description: {
                    Text("Добавьте счёт, чтобы загружать выписки.")
                } actions: {
                    Button("Добавить счёт") { showAdd = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                accountsList
            }
        }
        .navigationTitle("Банковские счета")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                AddBankAccountSheet {
                    showAdd = false
                    Task { await load() }
                }
            }
        }
        .alert("Удалить счёт?", isPresented: .init(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("Отмена", role: .cancel) { deleteTarget = nil }
            Button("Удалить", role: .destructive) {
                if let target = deleteTarget {
                    Task { await performDelete(target) }
                }
            }
        } message: {
            if let target = deleteTarget {
                Text(target.displayTitle)
            }
        }
    }

    // MARK: - List

    private var accountsList: some View {
        List {
            ForEach(accounts) { acc in
                accountRow(acc)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteTarget = acc
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func accountRow(_ acc: BankAccountItem) -> some View {
        HStack(spacing: 14) {
            bankIcon(acc.bankCode)

            VStack(alignment: .leading, spacing: 3) {
                Text(acc.bankName)
                    .font(.body.weight(.medium))

                if !acc.iban.isEmpty {
                    Text(acc.iban)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(acc.statementFrequencyLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func bankIcon(_ code: String) -> some View {
        let icon: String
        let color: Color
        switch code.lowercased() {
        case "kaspi":
            icon = "k.circle.fill"; color = .red
        case "halyk":
            icon = "h.circle.fill"; color = .green
        case "forte":
            icon = "f.circle.fill"; color = .blue
        case "bcc":
            icon = "b.circle.fill"; color = .purple
        default:
            icon = "building.columns.circle.fill"; color = .gray
        }
        return Image(systemName: icon)
            .font(.title)
            .foregroundStyle(color)
            .frame(width: 44, height: 44)
    }

    // MARK: - Data

    private func load() async {
        await MainActor.run {
            isLoading = true
            loadError = nil
        }
        do {
            let list = try await APIService.shared.bankAccounts()
            await MainActor.run {
                accounts = list
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func performDelete(_ acc: BankAccountItem) async {
        do {
            try await APIService.shared.deleteBankAccount(id: acc.id)
            await MainActor.run {
                accounts.removeAll { $0.id == acc.id }
                deleteTarget = nil
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                deleteTarget = nil
            }
        }
    }
}

// MARK: - Add Sheet

struct AddBankAccountSheet: View {
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var banks: [BankRef] = []
    @State private var frequencies: [FrequencyOption] = []
    @State private var selectedBankId: Int = 0
    @State private var iban = ""
    @State private var selectedFrequency = "EXISTING"
    @State private var isSubmitting = false
    @State private var formError: String?
    @State private var isLoadingBanks = true

    var body: some View {
        Form {
            if isLoadingBanks {
                Section {
                    ProgressView("Загрузка банков…")
                }
            } else {
                Section("Банк") {
                    Picker("Банк", selection: $selectedBankId) {
                        Text("Выберите…").tag(0)
                        ForEach(banks) { b in
                            Text(b.name).tag(b.id)
                        }
                    }
                }

                Section("IBAN") {
                    TextField("KZ...", text: $iban)
                        .textInputAutocapitalization(.characters)
                        .keyboardType(.asciiCapable)
                        .autocorrectionDisabled()
                }

                if !frequencies.isEmpty {
                    Section("Как часто используете") {
                        Picker("Частота", selection: $selectedFrequency) {
                            ForEach(frequencies, id: \.value) { f in
                                Text(f.label).tag(f.value)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                if let formError {
                    Section {
                        Label(formError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("Новый счёт")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Сохранить")
                    }
                }
                .disabled(isSubmitting || selectedBankId == 0)
            }
        }
        .interactiveDismissDisabled(isSubmitting)
        .task { await loadBanks() }
    }

    private func loadBanks() async {
        do {
            let resp = try await APIService.shared.banksList()
            await MainActor.run {
                banks = resp.banks
                frequencies = resp.frequencies
                if selectedBankId == 0, let first = resp.banks.first {
                    selectedBankId = first.id
                }
                isLoadingBanks = false
            }
        } catch {
            await MainActor.run {
                formError = error.localizedDescription
                isLoadingBanks = false
            }
        }
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        formError = nil
        defer { isSubmitting = false }

        do {
            _ = try await APIService.shared.addBankAccount(
                bankId: selectedBankId,
                iban: iban.trimmingCharacters(in: .whitespaces),
                statementFrequency: selectedFrequency
            )
            onFinished()
            dismiss()
        } catch {
            formError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        BankAccountsView()
    }
}
