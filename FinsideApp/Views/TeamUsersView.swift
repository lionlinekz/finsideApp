import SwiftUI

struct TeamUsersView: View {
    @State private var snapshot: TeamSnapshot?
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var selectedCompanyId: Int?
    @State private var showAdd = false

    var body: some View {
        Group {
            if isLoading && snapshot == nil {
                ProgressView("Загрузка…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError, snapshot == nil {
                ContentUnavailableView {
                    Label("Не удалось загрузить", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(err)
                } actions: {
                    Button("Повторить") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            } else if let snap = snapshot {
                teamList(snap: snap)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Пользователи")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if snapshot != nil {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showAdd) {
            if let snap = snapshot {
                NavigationStack {
                    TeamAddEmployeeSheet(snapshot: snap) {
                        showAdd = false
                        Task { await load() }
                    }
                }
            }
        }
    }

    // MARK: - List

    @ViewBuilder
    private func teamList(snap: TeamSnapshot) -> some View {
        if snap.companies.isEmpty {
            ContentUnavailableView(
                "Нет компаний",
                systemImage: "building.2",
                description: Text("Сначала добавьте компанию в веб-кабинете.")
            )
        } else {
            let cid = selectedCompanyId ?? snap.companies.first!.id
            let company = snap.companies.first { $0.id == cid } ?? snap.companies.first!

            VStack(spacing: 0) {
                if snap.companies.count > 1 {
                    companyPicker(snap: snap, cid: cid)
                }

                if company.positions.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Нет сотрудников")
                            .font(.title3.weight(.semibold))
                        Text("Нажмите «+» чтобы добавить первого пользователя.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    List {
                        ForEach(company.positions) { pos in
                            employeeRow(pos)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
    }

    private func companyPicker(snap: TeamSnapshot, cid: Int) -> some View {
        let binding = Binding(
            get: { cid },
            set: { selectedCompanyId = $0 }
        )
        return Picker("Компания", selection: binding) {
            ForEach(snap.companies) { c in
                Text(c.name).tag(c.id)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func employeeRow(_ pos: TeamPositionRow) -> some View {
        HStack(spacing: 14) {
            initialsCircle(pos)

            VStack(alignment: .leading, spacing: 3) {
                let fullName = "\(pos.firstName) \(pos.lastName)"
                    .trimmingCharacters(in: .whitespaces)
                Text(fullName.isEmpty ? pos.email : fullName)
                    .font(.body.weight(.medium))

                Text(pos.roleName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !pos.email.isEmpty {
                    Label(pos.email, systemImage: "envelope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !pos.phone.isEmpty {
                    Label(pos.phone, systemImage: "phone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !pos.pointsLabels.isEmpty {
                    Label(pos.pointsLabels.joined(separator: ", "), systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func initialsCircle(_ pos: TeamPositionRow) -> some View {
        let f = pos.firstName.prefix(1).uppercased()
        let l = pos.lastName.prefix(1).uppercased()
        let initials = (f + l).isEmpty ? "?" : f + l

        return Text(initials)
            .font(.headline)
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Color.accentColor.gradient, in: Circle())
    }

    // MARK: - Loading

    private func load() async {
        await MainActor.run {
            isLoading = true
            loadError = nil
        }
        do {
            let s = try await APIService.shared.teamSnapshot()
            await MainActor.run {
                snapshot = s
                if selectedCompanyId == nil {
                    selectedCompanyId = s.companies.first?.id
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

// MARK: - Add Employee Sheet

private enum TeamAddMode: String, CaseIterable, Identifiable, Hashable {
    case newEmployee = "Новый"
    case existing = "Существующий"
    var id: String { rawValue }
}

struct TeamAddEmployeeSheet: View {
    let snapshot: TeamSnapshot
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var mode: TeamAddMode = .newEmployee
    @State private var companyId: Int = 0
    @State private var roleId: Int = 0
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var telegramId = ""
    @State private var selectedPointIds = Set<Int>()
    @State private var availableProfiles: [AvailableProfileRow] = []
    @State private var selectedProfileId: Int?
    @State private var isSubmitting = false
    @State private var formError: String?
    @State private var showSuccess = false

    var body: some View {
        Form {
            Section {
                Picker("Тип", selection: $mode) {
                    ForEach(TeamAddMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Компания и роль") {
                Picker("Компания", selection: $companyId) {
                    ForEach(snapshot.companies) { c in
                        Text(c.name).tag(c.id)
                    }
                }
                Picker("Роль", selection: $roleId) {
                    ForEach(snapshot.roles) { r in
                        Text(r.name).tag(r.id)
                    }
                }
            }

            if selectedRole?.needPoints == true,
               let pts = currentCompany?.points, !pts.isEmpty {
                Section("Точки продаж") {
                    ForEach(pts) { p in
                        Toggle(p.address, isOn: bindingPoint(p.id))
                    }
                }
            }

            if mode == .newEmployee {
                newEmployeeFields
            } else {
                existingEmployeeFields
            }

            if let formError {
                Section {
                    Label(formError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Добавить сотрудника")
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
                .disabled(isSubmitting || !canSubmit)
            }
        }
        .interactiveDismissDisabled(isSubmitting)
        .onAppear {
            if companyId == 0, let first = snapshot.companies.first {
                companyId = first.id
            }
            if roleId == 0, let first = snapshot.roles.first {
                roleId = first.id
            }
        }
        .task(id: "\(companyId)-\(mode.rawValue)") {
            await loadProfilesIfNeeded()
        }
    }

    // MARK: - Form Sections

    private var newEmployeeFields: some View {
        Section("Данные сотрудника") {
            TextField("Имя", text: $firstName)
                .textContentType(.givenName)
            TextField("Фамилия", text: $lastName)
                .textContentType(.familyName)
            TextField("E-mail", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            TextField("Телефон", text: $phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
            TextField("Telegram ID", text: $telegramId)
                .keyboardType(.numbersAndPunctuation)
        }
    }

    private var existingEmployeeFields: some View {
        Section("Сотрудник") {
            if availableProfiles.isEmpty {
                Label("Нет доступных профилей", systemImage: "person.slash")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Профиль", selection: $selectedProfileId) {
                    Text("Выберите…").tag(nil as Int?)
                    ForEach(availableProfiles) { pr in
                        Text(pr.fullName).tag(pr.id as Int?)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var currentCompany: TeamCompany? {
        snapshot.companies.first { $0.id == companyId }
    }

    private var selectedRole: TeamRole? {
        snapshot.roles.first { $0.id == roleId }
    }

    private func bindingPoint(_ id: Int) -> Binding<Bool> {
        Binding(
            get: { selectedPointIds.contains(id) },
            set: { on in
                if on { selectedPointIds.insert(id) }
                else { selectedPointIds.remove(id) }
            }
        )
    }

    private var canSubmit: Bool {
        guard companyId != 0, roleId != 0 else { return false }
        if mode == .newEmployee {
            let ok = !firstName.trimmingCharacters(in: .whitespaces).isEmpty
                && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
                && !email.trimmingCharacters(in: .whitespaces).isEmpty
            if selectedRole?.needPoints == true,
               let pts = currentCompany?.points, !pts.isEmpty {
                return ok && !selectedPointIds.isEmpty
            }
            return ok
        }
        return selectedProfileId != nil && !availableProfiles.isEmpty
    }

    private func loadProfilesIfNeeded() async {
        guard mode == .existing else { return }
        do {
            let list = try await APIService.shared.teamAvailableProfiles(companyId: companyId)
            await MainActor.run {
                availableProfiles = list
                selectedProfileId = list.first?.id
                formError = nil
            }
        } catch {
            await MainActor.run {
                availableProfiles = []
                selectedProfileId = nil
                formError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        formError = nil
        defer { isSubmitting = false }
        let pids = Array(selectedPointIds).sorted()
        do {
            if mode == .newEmployee {
                try await APIService.shared.teamCreateEmployee(
                    companyId: companyId,
                    roleId: roleId,
                    email: email.trimmingCharacters(in: .whitespaces),
                    firstName: firstName.trimmingCharacters(in: .whitespaces),
                    lastName: lastName.trimmingCharacters(in: .whitespaces),
                    phone: phone.trimmingCharacters(in: .whitespaces),
                    telegramId: telegramId.trimmingCharacters(in: .whitespaces),
                    pointIds: pids
                )
            } else {
                guard let pid = selectedProfileId else { return }
                try await APIService.shared.teamAttachEmployee(
                    companyId: companyId,
                    roleId: roleId,
                    profileId: pid,
                    pointIds: pids
                )
            }
            onFinished()
            dismiss()
        } catch {
            formError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        TeamUsersView()
    }
}
