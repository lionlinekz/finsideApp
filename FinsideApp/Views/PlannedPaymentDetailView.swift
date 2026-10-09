import SwiftUI
import UniformTypeIdentifiers

/// Детали планового платежа: изменить сумму/дату (с областью применения для
/// повторяющихся), отметить исполненным — по транзакции из выписки, по
/// квитанции или без подтверждения.
struct PlannedPaymentDetailView: View {
    let event: CalendarEvent
    let onUpdate: (CalendarEvent) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var current: CalendarEvent
    @State private var activeSheet: ActiveSheet?
    @State private var isTogglingPlain = false
    @State private var showReceiptImporter = false
    @State private var isUploadingReceipt = false
    @State private var errorMessage: String?

    private enum ActiveSheet: Identifiable {
        case editAmount
        case editDate
        case matchCandidates
        var id: Int {
            switch self {
            case .editAmount: return 0
            case .editDate: return 1
            case .matchCandidates: return 2
            }
        }
    }

    init(event: CalendarEvent, onUpdate: @escaping (CalendarEvent) -> Void) {
        self.event = event
        self.onUpdate = onUpdate
        _current = State(initialValue: event)
    }

    /// Плановые платежи приходят с отрицательным id (см. `_planned_payment_to_dict`
    /// на бэкенде) — все новые эндпоинты принимают настоящий положительный pk.
    private var plannedPaymentId: Int { abs(current.id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    amountCard
                    dateCard

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    if current.isCompleted {
                        doneCard
                    } else {
                        markPaidSection
                    }
                }
                .padding(20)
            }
            .background(.background)
            .navigationTitle(current.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editAmount:
                AmountEditSheet(event: current, plannedPaymentId: plannedPaymentId, onSaved: apply)
            case .editDate:
                DateEditSheet(event: current, plannedPaymentId: plannedPaymentId, onSaved: apply)
            case .matchCandidates:
                MatchCandidatesSheet(event: current, plannedPaymentId: plannedPaymentId, onSaved: apply)
            }
        }
        .fileImporter(
            isPresented: $showReceiptImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await attachReceipt(from: url) }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func apply(_ updated: CalendarEvent) {
        current = updated
        onUpdate(updated)
        errorMessage = nil
    }

    // MARK: - Шапка

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(current.type.tint.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: current.isCompleted ? "checkmark" : current.type.icon)
                    .font(.title2)
                    .foregroundStyle(current.type.tint)
            }

            if current.isRecurring {
                Label("Повторяющийся платёж", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if !current.description.isEmpty {
                Text(current.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Сумма / дата

    private var amountCard: some View {
        InfoRow(
            icon: "banknote",
            title: "Сумма",
            value: current.formattedAmount ?? "—",
            actionTitle: "Изменить"
        ) { activeSheet = .editAmount }
    }

    private var dateCard: some View {
        InfoRow(
            icon: "calendar",
            title: "Дата",
            value: current.formattedDueDate,
            actionTitle: "Изменить"
        ) { activeSheet = .editDate }
    }

    // MARK: - Отметить исполненным

    private var markPaidSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Отметить как исполненный")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Button {
                activeSheet = .matchCandidates
            } label: {
                Label("Выбрать транзакцию из выписки", systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                errorMessage = nil
                showReceiptImporter = true
            } label: {
                ZStack {
                    Label("Прикрепить квитанцию", systemImage: "doc.text.fill")
                        .frame(maxWidth: .infinity)
                        .opacity(isUploadingReceipt ? 0 : 1)
                    if isUploadingReceipt { ProgressView().controlSize(.small) }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isUploadingReceipt)

            Button {
                Task { await togglePlain() }
            } label: {
                ZStack {
                    Label("Отметить без подтверждения", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                        .opacity(isTogglingPlain ? 0 : 1)
                    if isTogglingPlain { ProgressView().controlSize(.small) }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isTogglingPlain)
        }
    }

    private var doneCard: some View {
        VStack(spacing: 10) {
            Label("Исполнено", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)

            Button("Отменить отметку") {
                Task { await togglePlain() }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .disabled(isTogglingPlain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .liquidGlassCard(cornerRadius: 16)
    }

    // MARK: - Действия

    private func togglePlain() async {
        guard !isTogglingPlain else { return }
        isTogglingPlain = true
        defer { isTogglingPlain = false }
        do {
            let updated = try await APIService.shared.toggleCalendarEvent(eventId: current.id)
            apply(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func attachReceipt(from url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        isUploadingReceipt = true
        defer { isUploadingReceipt = false }
        do {
            let data = try Data(contentsOf: url)
            let name = url.lastPathComponent.isEmpty ? "receipt.pdf" : url.lastPathComponent
            let updated = try await APIService.shared.confirmPlannedPayment(
                id: plannedPaymentId,
                withReceiptData: data,
                fileName: name,
                mimeType: "application/pdf"
            )
            apply(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
            }

            Spacer()

            Button(actionTitle, action: action)
                .font(.subheadline.weight(.medium))
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 14)
    }
}

// MARK: - Изменить сумму

private struct AmountEditSheet: View {
    let event: CalendarEvent
    let plannedPaymentId: Int
    let onSaved: (CalendarEvent) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String
    @State private var scope = "this"
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(event: CalendarEvent, plannedPaymentId: Int, onSaved: @escaping (CalendarEvent) -> Void) {
        self.event = event
        self.plannedPaymentId = plannedPaymentId
        self.onSaved = onSaved
        _amountText = State(initialValue: event.amount ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("Сумма, ₸", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))

                if event.isRecurring {
                    ScopePicker(scope: $scope)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                Button {
                    save()
                } label: {
                    ZStack {
                        Text("Сохранить").opacity(isSaving ? 0 : 1)
                        if isSaving { ProgressView() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 22)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSaving || Double(amountText.replacingOccurrences(of: ",", with: ".")) == nil)
            }
            .padding(24)
            .navigationTitle("Сумма платежа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isSaving)
    }

    private func save() {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        guard Double(normalized) != nil else { return }
        isSaving = true
        Task {
            do {
                let updated = try await APIService.shared.updatePlannedPaymentAmount(
                    id: plannedPaymentId, amount: normalized, scope: scope
                )
                onSaved(updated)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Изменить дату

private struct DateEditSheet: View {
    let event: CalendarEvent
    let plannedPaymentId: Int
    let onSaved: (CalendarEvent) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date
    @State private var scope = "this"
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(event: CalendarEvent, plannedPaymentId: Int, onSaved: @escaping (CalendarEvent) -> Void) {
        self.event = event
        self.plannedPaymentId = plannedPaymentId
        self.onSaved = onSaved
        _selectedDate = State(initialValue: event.parsedDueDate ?? Date())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker("Дата", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()

                if event.isRecurring {
                    ScopePicker(scope: $scope)
                    if scope == "following" {
                        Text("Число месяца перенесётся на эту и все следующие записи серии.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                Button {
                    save()
                } label: {
                    ZStack {
                        Text("Сохранить").opacity(isSaving ? 0 : 1)
                        if isSaving { ProgressView() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 22)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSaving)
            }
            .padding(24)
            .navigationTitle("Дата платежа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.disabled(isSaving)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isSaving)
    }

    private func save() {
        isSaving = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: selectedDate)
        Task {
            do {
                let updated = try await APIService.shared.updatePlannedPaymentDate(
                    id: plannedPaymentId, date: dateString, scope: scope
                )
                onSaved(updated)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

/// «Только этот платёж» / «Этот и все следующие» — общий выбор области
/// применения для изменения суммы и даты повторяющегося платежа.
private struct ScopePicker: View {
    @Binding var scope: String

    var body: some View {
        Picker("Применить к", selection: $scope) {
            Text("Только этот").tag("this")
            Text("Этот и все следующие").tag("following")
        }
        .pickerStyle(.segmented)
    }
}

// MARK: - Подбор транзакции

private struct MatchCandidatesSheet: View {
    let event: CalendarEvent
    let plannedPaymentId: Int
    let onSaved: (CalendarEvent) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [PlannedPaymentCandidate] = []
    @State private var isLoading = true
    @State private var confirmingId: Int?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if candidates.isEmpty {
                    emptyState
                } else {
                    List(candidates) { candidate in
                        Button {
                            confirm(candidate)
                        } label: {
                            candidateRow(candidate)
                        }
                        .disabled(confirmingId != nil)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Выберите транзакцию")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .task { await load() }
            .overlay(alignment: .bottom) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                        .padding()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Подходящих транзакций из выписки не нашлось.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func candidateRow(_ candidate: PlannedPaymentCandidate) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.formattedAmount)
                    .font(.subheadline.weight(.semibold))
                Text(candidate.description.isEmpty ? candidate.bank : candidate.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(candidate.formattedDate)
                .font(.caption)
                .foregroundStyle(.secondary)
            if confirmingId == candidate.id {
                ProgressView().padding(.leading, 6)
            }
        }
        .foregroundStyle(.primary)
    }

    private func load() async {
        isLoading = true
        do {
            candidates = try await APIService.shared.plannedPaymentMatchCandidates(id: plannedPaymentId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func confirm(_ candidate: PlannedPaymentCandidate) {
        guard confirmingId == nil else { return }
        confirmingId = candidate.id
        errorMessage = nil
        Task {
            do {
                let updated = try await APIService.shared.confirmPlannedPayment(
                    id: plannedPaymentId, withTransactionId: candidate.id
                )
                onSaved(updated)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                confirmingId = nil
            }
        }
    }
}

#Preview {
    Text("PlannedPaymentDetailView")
}
