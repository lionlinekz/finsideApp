import SwiftUI
import UniformTypeIdentifiers

/// Кнопка «Загрузить выписку» на главном экране — рядом с «Добавить расход».
/// Пока ни одной выписки ещё не загружали, горит жёлтым, чтобы подсказать
/// следующий шаг; после первой успешной загрузки становится обычной,
/// как «Добавить расход». Прогресс отмечается тем же механизмом, что и
/// чек-лист онбординга (`completeOnboardingTask`), но этот id в сам
/// чек-лист не входит — это не обязательная задача, просто подсказка.
struct StatementUploadButton: View {
    @Environment(AppState.self) private var appState
    @Environment(ChatService.self) private var chatService

    @State private var showActionChoice = false
    @State private var showFileImporter = false
    @State private var showGuide = false
    @State private var isUploading = false
    @State private var resultAlert: ResultAlert?
    @State private var isGlowing = false

    /// Файл ждёт повторной попытки, пока пользователь регистрирует счёт —
    /// чтобы не просить выбрать его заново.
    @State private var pendingFile: (data: Data, fileName: String)?
    @State private var pendingBankAccountInfo: ImportNeedsBankAccount?
    @State private var showAddBankAccount = false

    private static let firstImportTaskId = "first_statement_import"

    private var hasImportedBefore: Bool {
        appState.user?.onboardingCompletedTasks.contains(Self.firstImportTaskId) ?? false
    }

    private struct ResultAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        Button {
            DashboardHaptics.lightImpact()
            showActionChoice = true
        } label: {
            HStack(spacing: 8) {
                if isUploading {
                    ProgressView()
                        .tint(hasImportedBefore ? .white : .black)
                } else {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.body.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                Text("Загрузить выписку")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .modifier(StatementButtonStyle(highlighted: !hasImportedBefore, glowing: isGlowing))
        }
        .buttonStyle(.dashboardPressable)
        .disabled(isUploading)
        .accessibilityHint("Загрузить банковскую выписку")
        .onAppear {
            guard !hasImportedBefore else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                isGlowing = true
            }
        }
        .confirmationDialog("Загрузить выписку", isPresented: $showActionChoice, titleVisibility: .visible) {
            Button("Выбрать файл") { showFileImporter = true }
            Button("Как выгрузить из приложения банка") { showGuide = true }
            Button("Отмена", role: .cancel) {}
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await upload(from: url) }
            case .failure(let error):
                resultAlert = ResultAlert(title: "Не удалось выбрать файл", message: error.localizedDescription)
            }
        }
        .sheet(isPresented: $showGuide) {
            StatementImportGuideView()
        }
        .sheet(isPresented: $showAddBankAccount) {
            NavigationStack {
                AddBankAccountSheet(
                    prefilledIban: pendingBankAccountInfo?.iban ?? "",
                    preselectBankCode: pendingBankAccountInfo?.guessedBankCode,
                    preselectBankId: pendingBankAccountInfo?.guessedBankId
                ) {
                    showAddBankAccount = false
                    Task { await retryPendingUpload() }
                }
            }
        }
        .alert(item: $resultAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("Понятно"))
            )
        }
    }

    private func upload(from url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let name = url.lastPathComponent.isEmpty ? "statement.txt" : url.lastPathComponent
            await performUpload(data: data, fileName: name)
        } catch {
            resultAlert = ResultAlert(title: "Не удалось прочитать файл", message: error.localizedDescription)
        }
    }

    private func retryPendingUpload() async {
        guard let pendingFile else { return }
        await performUpload(data: pendingFile.data, fileName: pendingFile.fileName)
    }

    /// Счёт для IBAN из выписки ещё не зарегистрирован — предлагаем завести
    /// его тут же, не отправляя пользователя на веб, и повторяем попытку сами.
    private func performUpload(data: Data, fileName: String) async {
        isUploading = true
        defer { isUploading = false }
        do {
            let response = try await chatService.uploadStatement(data: data, fileName: fileName)
            appState.completeOnboardingTask(Self.firstImportTaskId)

            if response.emptyImport == true {
                resultAlert = ResultAlert(
                    title: "Выписка распознана",
                    message: "Новых операций не нашлось — похоже, они уже были загружены раньше."
                )
            } else {
                let s = response.summary
                resultAlert = ResultAlert(
                    title: "Выписка загружена",
                    message: "Доходов: \(s.incomeCount) · Расходов: \(s.expenseCount) · Переводов: \(s.transferCount)"
                )
            }
        } catch let error as APIError {
            if case .needsBankAccount(let info) = error {
                pendingFile = (data, fileName)
                pendingBankAccountInfo = info
                showAddBankAccount = true
            } else {
                resultAlert = ResultAlert(title: "Не удалось загрузить выписку", message: error.localizedDescription)
            }
        } catch {
            resultAlert = ResultAlert(title: "Не удалось загрузить выписку", message: error.localizedDescription)
        }
    }
}

/// Жёлтая подсказка до первой загрузки, обычный стиль «Добавить расход» после.
private struct StatementButtonStyle: ViewModifier {
    let highlighted: Bool
    let glowing: Bool

    func body(content: Content) -> some View {
        if highlighted {
            content
                .foregroundStyle(.black)
                .background(Color.yellow, in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.yellow.opacity(0.8), lineWidth: 1)
                }
                .shadow(color: .yellow.opacity(glowing ? 0.55 : 0.15), radius: glowing ? 10 : 4)
        } else {
            content
                .foregroundStyle(.white)
                .liquidGlassCard(cornerRadius: 12)
        }
    }
}

// MARK: - Гид «как выгрузить выписку из приложения банка»

private struct BankGuideEntry: Identifiable {
    let id: String
    let name: String
}

/// Список банков как в `AddExpenseSheet` — держим отдельной копией, чтобы не
/// тащить зависимость между несвязанными экранами.
private let statementGuideBanks: [BankGuideEntry] = [
    BankGuideEntry(id: "kaspi", name: "Kaspi"),
    BankGuideEntry(id: "halyk", name: "Halyk"),
    BankGuideEntry(id: "forte", name: "Forte"),
    BankGuideEntry(id: "altyn", name: "Altyn"),
    BankGuideEntry(id: "bcc", name: "CenterCredit"),
    BankGuideEntry(id: "eurasian", name: "Евразийский"),
    BankGuideEntry(id: "jusan", name: "Jusan"),
    BankGuideEntry(id: "otbasy", name: "Отбасы"),
]

private struct StatementImportGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Finside принимает выписку текстовым файлом (.txt). Экспортируйте её в приложении своего банка и выберите файл здесь — либо просто поделитесь им из банковского приложения прямо в Finside через «Поделиться».")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 10) {
                        ForEach(statementGuideBanks) { bank in
                            BankGuideRow(bank: bank)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Как загрузить выписку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }.appScreenBackground()
    }
}

private struct BankGuideRow: View {
    let bank: BankGuideEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bank.name)
                .font(.subheadline.weight(.semibold))
            // TODO: заменить на реальные шаги экспорта выписки для каждого банка.
            Text("Инструкция скоро появится")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.appSurface, in: .rect(cornerRadius: 14))
    }
}

#Preview {
    StatementUploadButton()
        .environment(AppState())
        .environment(ChatService())
        .padding()
}
