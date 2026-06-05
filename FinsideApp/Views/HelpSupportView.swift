import SwiftUI

struct HelpSupportView: View {
    @Environment(AppState.self) private var appState
    @State private var showAgreementSheet = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var banner: Banner?

    private struct Banner: Identifiable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    var body: some View {
        List {
            Section {
                Label {
                    Text("По вопросам обучения и работы сервиса пишите в каналы поддержки в приложении или на почту вашего менеджера.")
                } icon: {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(role: .destructive) {
                    showAgreementSheet = true
                } label: {
                    Label("Удалить все транзакции", systemImage: "trash")
                }
                .disabled(isDeleting)
            } footer: {
                Text(
                    "Навсегда удаляются все доходы и расходы в организации, а также история импортов банковских выписок. Заявки на оплату, компании и счета не затрагиваются. Действие необратимо."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Помощь и поддержка")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showAgreementSheet) {
            VoluntaryDataDeletionAgreementView(
                user: appState.user,
                onAgreementAcceptedDelete: {
                    showAgreementSheet = false
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        showDeleteConfirm = true
                    }
                }
            )
        }
        .confirmationDialog(
            "Удалить все транзакции?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Удалить всё", role: .destructive) {
                Task { await runDelete() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Это нельзя отменить. Убедитесь, что у вас есть резервная копия данных при необходимости.")
        }
        .overlay {
            if isDeleting {
                ProgressView("Удаление…")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .alert(item: $banner) { item in
            Alert(
                title: Text(item.isError ? "Ошибка" : "Готово"),
                message: Text(item.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func runDelete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            let r = try await APIService.shared.deleteAllTransactionsConfirmed()
            NotificationCenter.default.post(name: .finsideLedgerDidChange, object: nil)
            banner = Banner(
                message:
                    "Удалено операций: доходов \(r.deletedIncomes), расходов \(r.deletedPayments). Загрузок выписок: \(r.deletedStatementUploads).",
                isError: false
            )
        } catch {
            banner = Banner(message: error.localizedDescription, isError: true)
        }
    }
}

// MARK: - Соглашение о добровольном удалении

private struct VoluntaryDataDeletionAgreementView: View {
    let user: UserInfo?
    /// После нажатия «Удалить» (родитель закрывает cover и открывает финальный диалог).
    var onAgreementAcceptedDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var hasScrolledToBottom = false
    @State private var confirmedHasDataCopies = false
    @State private var confirmedDataExported = false
    @State private var confirmedNoRetentionRequirements = false
    @State private var acceptedTerms = false

    private var allPrerequisitesConfirmed: Bool {
        confirmedHasDataCopies && confirmedDataExported && confirmedNoRetentionRequirements
    }

    private var canDelete: Bool {
        hasScrolledToBottom && allPrerequisitesConfirmed && acceptedTerms
    }

    private var agreementDateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.setLocalizedDateFormatFromTemplate("dMMMMYYYY")
        return f.string(from: Date())
    }

    private var userPartyLine: String {
        guard let u = user else { return "—" }
        let name = [u.firstName, u.lastName].filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if let co = u.companyName?.trimmingCharacters(in: .whitespaces), !co.isEmpty {
            if name.isEmpty { return co }
            return "\(name) · \(co)"
        }
        if !name.isEmpty { return name }
        return u.email
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text("СОГЛАШЕНИЕ О ДОБРОВОЛЬНОМ УДАЛЕНИИ ДАННЫХ")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(
                        "Я подтверждаю, что добровольно инициирую удаление своих данных из платформы Finside."
                    )
                    .font(.body)

                    Text("Перед удалением данных подтвердите каждый пункт:")
                        .font(.body.weight(.semibold))

                    VStack(alignment: .leading, spacing: 0) {
                        prerequisiteToggle(
                            isOn: $confirmedHasDataCopies,
                            text: "У меня есть копии удаляемых данных, отчёты из платформы получены в полном объёме."
                        )
                        Divider().padding(.leading, 16)
                        prerequisiteToggle(
                            isOn: $confirmedDataExported,
                            text: "Вся необходимая информация выгружена и проверена."
                        )
                        Divider().padding(.leading, 16)
                        prerequisiteToggle(
                            isOn: $confirmedNoRetentionRequirements,
                            text: "У меня нет дополнительных требований по сохранению данных."
                        )
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color(.separator), lineWidth: 0.5)
                    )

                    if !allPrerequisitesConfirmed {
                        Label(
                            "Отметьте все три пункта, чтобы подтвердить соглашение.",
                            systemImage: "checkmark.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }

                    Text(
                        "Я подтверждаю, что после удаления данных не буду иметь каких-либо претензий к компании Finside, её сотрудникам и партнёрам, связанных с удалением данных, невозможностью их восстановления, потерей информации либо иными последствиями удаления данных."
                    )
                    .font(.body)

                    Text("Компания Finside не несёт ответственность за:")
                        .font(.body.weight(.semibold))

                    agreementBullet("утрату данных после их удаления;")
                    agreementBullet("невозможность восстановления удалённых данных;")
                    agreementBullet("последствия, связанные с удалением данных по инициативе клиента.")

                    Text(
                        "Finside подтверждает, что в результате данного действия настройки аккаунта не удаляются и продолжают сохраняться в платформе."
                    )
                    .font(.body)

                    Text("В случае необходимости изменения или удаления настроек требуется отдельное обращение.")
                        .font(.body)

                    Text("Подтверждение данного соглашения означает полное согласие с вышеуказанными условиями.")
                        .font(.body.weight(.semibold))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Дата: \(agreementDateLabel)")
                        Text("ФИО / Компания: \(userPartyLine)")
                        Text("Подпись: подтверждается отметкой всех пунктов и нажатием «Удалить».")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .font(.body)
                    .padding(.vertical, 8)

                    Toggle(isOn: $acceptedTerms) {
                        Text(
                            "Я прочитал(а) текст до конца и подтверждаю полное согласие с условиями соглашения."
                        )
                        .font(.subheadline)
                    }
                    .tint(.accentColor)
                    .disabled(!allPrerequisitesConfirmed)
                    .opacity(allPrerequisitesConfirmed ? 1 : 0.45)
                    .padding(.top, 4)
                    .onChange(of: allPrerequisitesConfirmed) { _, isConfirmed in
                        if !isConfirmed {
                            acceptedTerms = false
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            hasScrolledToBottom = true
                        }
                        .padding(.bottom, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("Соглашение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Удалить", role: .destructive) {
                        guard canDelete else { return }
                        onAgreementAcceptedDelete()
                    }
                    .disabled(!canDelete)
                }
            }
        }
    }

    private func prerequisiteToggle(isOn: Binding<Bool>, text: String) -> some View {
        Toggle(isOn: isOn) {
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(.accentColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func agreementBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.body.weight(.bold))
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        HelpSupportView()
    }
    .environment(AppState())
}
