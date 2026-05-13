import SwiftUI

struct BranchesView: View {
    @State private var companies: [BranchCompany] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var showAddCompany = false
    @State private var editCompany: BranchCompany?
    @State private var addPointTarget: BranchCompany?
    @State private var deletePointTarget: BranchPoint?

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
                    VStack(spacing: 10) {
                        Button("Повторить") { Task { await load() } }
                            .buttonStyle(.bordered)
                        Button("Добавить компанию") { showAddCompany = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else if companies.isEmpty {
                ContentUnavailableView {
                    Label("Нет компаний", systemImage: "building.2")
                } description: {
                    Text("Добавьте компанию, чтобы управлять филиалами.")
                } actions: {
                    Button("Добавить компанию") { showAddCompany = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                companiesList
            }
        }
        .navigationTitle("Филиалы")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddCompany = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showAddCompany) {
            NavigationStack {
                AddCompanySheet {
                    showAddCompany = false
                    Task { await load() }
                }
            }
        }
        .sheet(item: $editCompany) { company in
            NavigationStack {
                EditCompanySheet(company: company) {
                    editCompany = nil
                    Task { await load() }
                }
            }
        }
        .sheet(item: $addPointTarget) { company in
            NavigationStack {
                AddPointSheet(company: company) {
                    addPointTarget = nil
                    Task { await load() }
                }
            }
        }
        .alert("Удалить филиал?", isPresented: .init(
            get: { deletePointTarget != nil },
            set: { if !$0 { deletePointTarget = nil } }
        )) {
            Button("Отмена", role: .cancel) { deletePointTarget = nil }
            Button("Удалить", role: .destructive) {
                if let target = deletePointTarget {
                    Task { await performDeletePoint(target) }
                }
            }
        } message: {
            if let target = deletePointTarget {
                Text(target.address)
            }
        }
    }

    // MARK: - List

    private var companiesList: some View {
        BranchesListContent(
            companies: companies,
            onEditCompany: { company in editCompany = company },
            onAddPoint: { company in addPointTarget = company },
            onDeletePoint: { point in deletePointTarget = point }
        )
    }

    // MARK: - Data

    private func load() async {
        await MainActor.run {
            isLoading = true
            loadError = nil
        }
        do {
            let list = try await APIService.shared.branches()
            await MainActor.run {
                companies = list
                isLoading = false
            }
        } catch {
            let msg = error.localizedDescription
            let is404 = msg.contains("404") || msg.contains("Not Found")
            await MainActor.run {
                if is404 {
                    companies = []
                } else {
                    loadError = msg
                }
                isLoading = false
            }
        }
    }

    private func performDeletePoint(_ point: BranchPoint) async {
        do {
            try await APIService.shared.deletePoint(id: point.id)
            await MainActor.run {
                deletePointTarget = nil
            }
            await load()
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                deletePointTarget = nil
            }
        }
    }
}

// MARK: - List Content (separate view to avoid @State / Binding overload ambiguity)

private struct BranchesListContent: View {
    let companies: [BranchCompany]
    var onEditCompany: (BranchCompany) -> Void
    var onAddPoint: (BranchCompany) -> Void
    var onDeletePoint: (BranchPoint) -> Void

    var body: some View {
        List {
            ForEach(companies, id: \.id) { (company: BranchCompany) in
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        companyHeader(company)
                        Button {
                            onEditCompany(company)
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Редактировать компанию")
                    }

                    ForEach(company.points, id: \.id) { (point: BranchPoint) in
                        pointRow(point)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    onDeletePoint(point)
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                    }

                    Button {
                        onAddPoint(company)
                    } label: {
                        Label("Добавить филиал", systemImage: "plus.circle")
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func companyHeader(_ company: BranchCompany) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(companyTypeColor(company.companyType).opacity(0.15))
                    .frame(width: 44, height: 44)
                Text(company.companyTypeLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(companyTypeColor(company.companyType))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(company.name)
                    .font(.body.weight(.semibold))

                HStack(spacing: 8) {
                    Text(company.bin)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if !company.taxModeLabel.isEmpty {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(company.taxModeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !company.direction.isEmpty {
                    Text(company.direction)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func pointRow(_ point: BranchPoint) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            Text(point.address)
                .font(.subheadline)
        }
        .padding(.vertical, 2)
    }

    private func companyTypeColor(_ type: String) -> Color {
        switch type {
        case "IP": return .blue
        case "TOO": return .purple
        default: return .secondary
        }
    }
}

// MARK: - Add Company Sheet

struct AddCompanySheet: View {
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var bin = ""
    @State private var companyType = "TOO"
    @State private var direction = ""
    @State private var taxMode = ""
    @State private var address = ""
    @State private var isSubmitting = false
    @State private var formError: String?

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && bin.trimmingCharacters(in: .whitespaces).count == 12
    }

    var body: some View {
        Form {
            Section("Тип компании") {
                Picker("Тип", selection: $companyType) {
                    Text("ИП").tag("IP")
                    Text("ТОО").tag("TOO")
                }
                .pickerStyle(.segmented)
            }

            Section("Основные данные") {
                TextField("Название", text: $name)
                TextField("ИИН/БИН (12 цифр)", text: $bin)
                    .keyboardType(.numberPad)
                TextField("Направление (необязательно)", text: $direction)
            }

            Section("Налоговый режим") {
                Picker("Режим", selection: $taxMode) {
                    Text("Не указан").tag("")
                    Text("Патент (1%)").tag("PATENT")
                    Text("Упрощённый (3%)").tag("USN")
                    Text("Общий (10%)").tag("OUR")
                }
            }

            Section("Первый филиал (необязательно)") {
                TextField("Адрес", text: $address)
            }

            if let formError {
                Section {
                    Label(formError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Новая компания")
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
                .disabled(!canSubmit || isSubmitting)
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        formError = nil
        defer { isSubmitting = false }

        do {
            _ = try await APIService.shared.addCompany(
                name: name.trimmingCharacters(in: .whitespaces),
                bin: bin.trimmingCharacters(in: .whitespaces),
                companyType: companyType,
                direction: direction.trimmingCharacters(in: .whitespaces),
                taxMode: taxMode,
                address: address.trimmingCharacters(in: .whitespaces)
            )
            onFinished()
            dismiss()
        } catch {
            formError = error.localizedDescription
        }
    }
}

// MARK: - Edit Company Sheet

struct EditCompanySheet: View {
    let company: BranchCompany
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var direction: String
    @State private var taxMode: String
    @State private var isSubmitting = false
    @State private var formError: String?

    init(company: BranchCompany, onFinished: @escaping () -> Void) {
        self.company = company
        self.onFinished = onFinished
        _name = State(initialValue: company.name)
        _direction = State(initialValue: company.direction)
        _taxMode = State(initialValue: company.taxMode)
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section("Компания") {
                LabeledContent("ИИН/БИН", value: company.bin)
                LabeledContent("Тип", value: company.companyTypeLabel)
            }

            Section("Данные") {
                TextField("Название", text: $name)
                TextField("Направление (необязательно)", text: $direction)
            }

            Section("Налоговый режим") {
                Picker("Режим", selection: $taxMode) {
                    Text("Не указан").tag("")
                    if company.companyType != "TOO" {
                        Text("Патент (1%)").tag("PATENT")
                    }
                    Text("Упрощённый (3%)").tag("USN")
                    Text("Общий (10%)").tag("OUR")
                }
            }

            if let formError {
                Section {
                    Label(formError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Компания")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if company.companyType == "TOO" && taxMode == "PATENT" {
                taxMode = ""
            }
        }
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
                .disabled(!canSubmit || isSubmitting)
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        formError = nil
        defer { isSubmitting = false }

        do {
            _ = try await APIService.shared.editCompany(
                id: company.id,
                name: name.trimmingCharacters(in: .whitespaces),
                direction: direction.trimmingCharacters(in: .whitespaces),
                taxMode: taxMode
            )
            onFinished()
            dismiss()
        } catch {
            formError = error.localizedDescription
        }
    }
}

// MARK: - Add Point Sheet

struct AddPointSheet: View {
    let company: BranchCompany
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var isSubmitting = false
    @State private var formError: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Компания")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(company.name)
                }
            }

            Section("Адрес филиала") {
                TextField("ул. Примерная, д. 1", text: $address)
            }

            if let formError {
                Section {
                    Label(formError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Новый филиал")
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
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        formError = nil
        defer { isSubmitting = false }

        do {
            _ = try await APIService.shared.addPoint(
                companyId: company.id,
                address: address.trimmingCharacters(in: .whitespaces)
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
        BranchesView()
    }
}
