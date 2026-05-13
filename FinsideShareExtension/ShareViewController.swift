import SwiftUI
import UniformTypeIdentifiers

@objc(ShareViewController)
class ShareViewController: UIViewController {
    private var hostingController: UIHostingController<ShareView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        let shareView = ShareView(
            extensionContext: extensionContext,
            onComplete: { [weak self] conversationId in
                self?.openMainApp(conversationId: conversationId)
            },
            onCancel: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        )

        let hosting = UIHostingController(rootView: shareView)
        hostingController = hosting
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hosting.didMove(toParent: self)
    }

    /// Открывает основное приложение через NSExtensionContext (UIApplication из extension недоступен).
    private func openMainApp(conversationId: Int?) {
        guard let id = conversationId,
              let url = URL(string: "finside://chat/\(id)") else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        extensionContext?.open(url) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}

// MARK: - ShareView

struct ShareView: View {
    /// Симулятор → localhost; физ. устройство и Release → finside.pro (как `BackendEnvironment` в приложении).
    private static var apiBaseURL: String {
        #if DEBUG
        #if targetEnvironment(simulator)
        return "http://127.0.0.1:8000/api"
        #else
        return "https://finside.pro/api"
        #endif
        #else
        return "https://finside.pro/api"
        #endif
    }

    private static let appGroupSuite = "group.kz.finside.app"
    private static let sharedAccessTokenKey = "shared_access_token"

    let extensionContext: NSExtensionContext?
    let onComplete: (Int?) -> Void
    let onCancel: () -> Void

    @State private var status: ShareStatus = .loading
    @State private var fileName = ""
    @State private var resultText = ""
    @State private var pendingFileData: (Data, String)?
    // Inline add-bank-account form state
    @State private var availableBanks: [ShareBankRef] = []
    @State private var selectedBankId: Int = 0
    @State private var ibanField = ""
    @State private var isAddingAccount = false
    @State private var addAccountError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                switch status {
                case .loading:
                    ProgressView("Загрузка файла...")
                        .progressViewStyle(.circular)

                case .uploading:
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.5)
                        Text("Импорт выписки")
                            .font(.headline)
                        Text(fileName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                case .success:
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.green)
                        Text("Выписка отправлена")
                            .font(.headline)
                        Text(resultText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Text("Открываем канал со счётом…")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                case .error(let message):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.orange)
                        Text("Ошибка")
                            .font(.headline)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                case .noAuth:
                    VStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.secondary)
                        Text("Необходима авторизация")
                            .font(.headline)
                        Text("Откройте Finside и войдите в аккаунт — тогда расшаривание сработает.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                case .needsBankAccount(let info):
                    needsBankAccountForm(info: info)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Finside")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { onCancel() }
                }
            }
        }
        .task {
            await processSharedFile()
        }
    }

    private func readSharedAccessToken() -> String? {
        UserDefaults(suiteName: Self.appGroupSuite)?.string(forKey: Self.sharedAccessTokenKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private func processSharedFile() async {
        guard let token = readSharedAccessToken() else {
            status = .noAuth
            return
        }

        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else {
            status = .error("Файл не найден")
            return
        }

        do {
            let (data, name) = try await loadSharedFile(from: provider)
            fileName = name
            pendingFileData = (data, name)
            status = .uploading

            let result = try await uploadStatement(data: data, fileName: name, token: token)
            handleImportSuccess(result)
        } catch let err as ShareError {
            if case .needsBankAccount(let iban, let code, let bankId) = err,
               let token = readSharedAccessToken() {
                let (data, name) = pendingFileData ?? (Data(), fileName)
                status = .needsBankAccount(ShareNeedsBankInfo(
                    iban: iban,
                    guessedBankCode: code,
                    guessedBankId: bankId,
                    fileData: data,
                    fileName: name,
                    token: token
                ))
            } else {
                status = .error(err.localizedDescription)
            }
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    // MARK: - Needs Bank Account Form

    private func needsBankAccountForm(info: ShareNeedsBankInfo) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "building.columns.circle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Счёт не зарегистрирован")
                .font(.headline)

            if !info.iban.isEmpty {
                Text("IBAN: \(info.iban)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text("Добавьте банковский счёт, и выписка будет импортирована автоматически.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            if availableBanks.isEmpty && addAccountError == nil {
                ProgressView("Загрузка банков…")
                    .task { await loadBanksForForm(token: info.token, info: info) }
            } else {
                VStack(spacing: 12) {
                    Picker("Банк", selection: $selectedBankId) {
                        Text("Выберите банк…").tag(0)
                        ForEach(availableBanks) { b in
                            Text(b.name).tag(b.id)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("IBAN", text: $ibanField)
                        .textInputAutocapitalization(.characters)
                        .keyboardType(.asciiCapable)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    if let addAccountError {
                        Label(addAccountError, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await addAccountAndRetry(info: info) }
                    } label: {
                        HStack {
                            if isAddingAccount {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            }
                            Text("Добавить счёт и импортировать")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedBankId == 0 || isAddingAccount)
                }
                .padding(.horizontal)
            }
        }
    }

    private func loadBanksForForm(token: String, info: ShareNeedsBankInfo) async {
        do {
            let banks = try await fetchBanks(token: token)
            await MainActor.run {
                availableBanks = banks
                ibanField = info.iban
                if let gid = info.guessedBankId {
                    selectedBankId = gid
                } else if !info.guessedBankCode.isEmpty,
                          let match = banks.first(where: { $0.code == info.guessedBankCode }) {
                    selectedBankId = match.id
                }
            }
        } catch {
            await MainActor.run {
                addAccountError = error.localizedDescription
            }
        }
    }

    private func addAccountAndRetry(info: ShareNeedsBankInfo) async {
        await MainActor.run {
            isAddingAccount = true
            addAccountError = nil
        }

        do {
            try await addBankAccount(
                bankId: selectedBankId,
                iban: ibanField.trimmingCharacters(in: .whitespaces),
                token: info.token
            )

            await MainActor.run { status = .uploading }

            let result = try await uploadStatement(
                data: info.fileData,
                fileName: info.fileName,
                token: info.token
            )
            await MainActor.run { handleImportSuccess(result) }
        } catch {
            await MainActor.run {
                isAddingAccount = false
                addAccountError = error.localizedDescription
            }
        }
    }

    private func handleImportSuccess(_ result: ShareImportResponse) {
        let total = result.summary.incomeCount + result.summary.expenseCount + result.summary.transferCount
        resultText =
            "Новых операций: \(total) (доходов \(result.summary.incomeCount), расходов \(result.summary.expenseCount), переводов \(result.summary.transferCount))."
        status = .success

        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run {
                onComplete(result.conversationId)
            }
        }
    }

    /// Поддержка .txt из «Файлы», банковских приложений (file-url, plain text).
    private func loadSharedFile(from provider: NSItemProvider) async throws -> (Data, String) {
        let typeOrder = [
            UTType.plainText.identifier,
            "public.plain-text",
            "public.text",
            "public.utf8-plain-text",
            "public.file-url",
        ]

        for typeId in typeOrder {
            guard provider.hasItemConformingToTypeIdentifier(typeId) else { continue }

            let item = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Any?, Error>) in
                provider.loadItem(forTypeIdentifier: typeId, options: nil) { object, err in
                    if let err {
                        cont.resume(throwing: err)
                    } else {
                        cont.resume(returning: object)
                    }
                }
            }

            if typeId == "public.file-url" {
                let url: URL? = {
                    if let u = item as? URL { return u }
                    if let ns = item as? NSURL { return ns as URL }
                    return nil
                }()
                guard let url else { continue }
                let name = url.lastPathComponent
                let lower = name.lowercased()
                guard lower.hasSuffix(".txt") || lower.hasSuffix(".text") else {
                    continue
                }
                let data = try Data(contentsOf: url)
                return (data, name)
            }

            if let url = item as? URL {
                let data = try Data(contentsOf: url)
                return (data, url.lastPathComponent.isEmpty ? "statement.txt" : url.lastPathComponent)
            }
            if let url = item as? NSURL, let u = url as URL? {
                let data = try Data(contentsOf: u)
                let name = u.lastPathComponent.isEmpty ? "statement.txt" : u.lastPathComponent
                return (data, name)
            }
            if let str = item as? String {
                return (Data(str.utf8), "statement.txt")
            }
            if let data = item as? Data {
                return (data, "statement.txt")
            }
        }

        throw ShareError.unsupportedType
    }

    private func uploadStatement(data: Data, fileName: String, token: String) async throws -> ShareImportResponse {
        let baseURL = Self.apiBaseURL

        guard let url = URL(string: "\(baseURL)/chat/import-statement/") else {
            throw URLError(.badURL)
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/plain\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if !(200...299).contains(http.statusCode) {
            if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               json["needs_bank_account"] as? Bool == true {
                throw ShareError.needsBankAccount(
                    iban: json["iban"] as? String ?? "",
                    guessedBankCode: json["guessed_bank_code"] as? String ?? "",
                    guessedBankId: json["guessed_bank_id"] as? Int
                )
            }
            if let apiErr = try? JSONDecoder().decode(ShareAPIError.self, from: responseData),
               !apiErr.error.isEmpty {
                throw ShareError.server(apiErr.error)
            }
            let snippet = String(data: responseData.prefix(200), encoding: .utf8) ?? ""
            throw ShareError.server("Сервер: \(http.statusCode) \(snippet)")
        }

        return try JSONDecoder().decode(ShareImportResponse.self, from: responseData)
    }

    // MARK: - Bank Account helpers (for inline add-account flow)

    private func fetchBanks(token: String) async throws -> [ShareBankRef] {
        let baseURL = Self.apiBaseURL
        guard let url = URL(string: "\(baseURL)/bank-accounts/banks/") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let resp = try JSONDecoder().decode(ShareBanksListResponse.self, from: data)
        return resp.banks
    }

    private func addBankAccount(bankId: Int, iban: String, token: String) async throws {
        let baseURL = Self.apiBaseURL
        guard let url = URL(string: "\(baseURL)/bank-accounts/add/") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["bank_id": bankId, "iban": iban]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errMsg = json["error"] as? String {
                throw ShareError.server(errMsg)
            }
            throw ShareError.server("Не удалось добавить счёт (\(http.statusCode))")
        }
    }
}

private enum ShareError: LocalizedError {
    case unsupportedType
    case server(String)
    case needsBankAccount(iban: String, guessedBankCode: String, guessedBankId: Int?)

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            return "Нужен текстовый файл выписки (.txt). Если банк отдаёт PDF — сохраните как .txt или откройте выписку в приложении Finside."
        case .server(let msg):
            return msg
        case .needsBankAccount:
            return "Банковский счёт не зарегистрирован"
        }
    }
}

private struct ShareAPIError: Decodable {
    let error: String
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Types

enum ShareStatus {
    case loading
    case uploading
    case success
    case error(String)
    case noAuth
    /// The IBAN from the statement is not registered — offer to add it.
    case needsBankAccount(ShareNeedsBankInfo)
}

struct ShareNeedsBankInfo {
    let iban: String
    let guessedBankCode: String
    let guessedBankId: Int?
    let fileData: Data
    let fileName: String
    let token: String
}

struct ShareImportResponse: Codable {
    let conversationId: Int
    let messageId: Int
    let summary: ShareImportSummary

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case messageId = "message_id"
        case summary
    }
}

struct ShareBankRef: Codable, Identifiable {
    let id: Int
    let name: String
    let code: String
}

struct ShareBanksListResponse: Codable {
    let banks: [ShareBankRef]
}

struct ShareImportSummary: Codable {
    let incomeCount: Int
    let expenseCount: Int
    let transferCount: Int

    enum CodingKeys: String, CodingKey {
        case incomeCount = "income_count"
        case expenseCount = "expense_count"
        case transferCount = "transfer_count"
    }
}
