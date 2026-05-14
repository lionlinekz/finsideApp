import Foundation

extension Notification.Name {
    /// Posted after access/refresh tokens are saved (login or refresh). WebSocket should reconnect.
    static let finsideTokensRefreshed = Notification.Name("finside.tokensRefreshed")
    /// Все операции доходов/расходов в тенанте удалены (например из настроек).
    static let finsideLedgerDidChange = Notification.Name("finside.ledgerDidChange")
}

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let user: UserInfo

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

struct RefreshResponse: Codable {
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

struct UserInfo: Codable {
    let id: Int
    let email: String
    let firstName: String
    let lastName: String
    let brandName: String
    let phoneVerified: Bool
    let isVerified: Bool
    /// Абсолютный URL медиафайла, если аватар загружен в веб-настройках.
    let avatarURL: String?
    /// Наименование роли в тенанте (из Position), если есть.
    let jobTitle: String?
    /// Компания первой позиции, если привязана.
    let companyName: String?

    enum CodingKeys: String, CodingKey {
        case id, email
        case firstName = "first_name"
        case lastName = "last_name"
        case brandName = "brand_name"
        case phoneVerified = "phone_verified"
        case isVerified = "is_verified"
        case avatarURL = "avatar_url"
        case jobTitle = "job_title"
        case companyName = "company_name"
    }
}

struct MeResponse: Codable {
    let user: UserInfo
}

struct ErrorResponse: Codable {
    let error: String
}

struct DeleteAllTransactionsResponse: Codable {
    let ok: Bool
    let deletedIncomes: Int
    let deletedPayments: Int
    let deletedStatementUploads: Int

    enum CodingKeys: String, CodingKey {
        case ok
        case deletedIncomes = "deleted_incomes"
        case deletedPayments = "deleted_payments"
        case deletedStatementUploads = "deleted_statement_uploads"
    }
}


enum APIError: LocalizedError {
    case invalidURL
    case serverError(String)
    case unauthorized
    case networkError(Error)
    /// The imported statement references an unregistered bank account.
    case needsBankAccount(ImportNeedsBankAccount)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .serverError(let msg): return msg
        case .unauthorized: return "Session expired"
        case .networkError(let err): return err.localizedDescription
        case .needsBankAccount(let info): return info.errorMessage
        }
    }
}

final class APIService {
    static let shared = APIService()

    private let baseURL = BackendEnvironment.apiBaseURL

    private init() {}

    // MARK: - Login

    func login(email: String, password: String) async throws -> AuthResponse {
        let body: [String: String] = ["email": email, "password": password]
        let data = try await post(path: "/auth/login/", body: body)
        if let errResp = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           !errResp.error.isEmpty {
            throw APIError.serverError(errResp.error)
        }
        let resp = try JSONDecoder().decode(AuthResponse.self, from: data)
        KeychainService.save(key: .accessToken, value: resp.accessToken)
        KeychainService.save(key: .refreshToken, value: resp.refreshToken)
        NotificationCenter.default.post(name: .finsideTokensRefreshed, object: nil)
        return resp
    }

    // MARK: - Refresh

    func refreshTokens() async throws -> RefreshResponse {
        guard let raw = KeychainService.read(key: .refreshToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else {
            throw APIError.unauthorized
        }
        let body: [String: String] = ["refresh_token": raw]
        let data = try await post(path: "/auth/refresh/", body: body)
        if let errResp = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           !errResp.error.isEmpty {
            throw APIError.unauthorized
        }
        let resp = try JSONDecoder().decode(RefreshResponse.self, from: data)
        KeychainService.save(key: .accessToken, value: resp.accessToken)
        KeychainService.save(key: .refreshToken, value: resp.refreshToken)
        NotificationCenter.default.post(name: .finsideTokensRefreshed, object: nil)
        return resp
    }

    // MARK: - Me

    func me() async throws -> UserInfo {
        let data = try await get(path: "/auth/me/")
        let resp = try JSONDecoder().decode(MeResponse.self, from: data)
        return resp.user
    }

    // MARK: - Dashboard

    func dashboard(period: String, date: String? = nil) async throws -> DashboardResponse {
        var path = "/dashboard/?period=\(period)"
        if let date { path += "&date=\(date)" }
        let data = try await get(path: path)

        if let errResp = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           !errResp.error.isEmpty {
            throw APIError.serverError(errResp.error)
        }

        do {
            return try JSONDecoder().decode(DashboardResponse.self, from: data)
        } catch {
            #if DEBUG
            if let raw = String(data: data, encoding: .utf8) {
                print("Dashboard decode error. Raw response:\n\(raw.prefix(500))")
            }
            #endif
            throw error
        }
    }

    // MARK: - Dashboard ledger (drill-down)

    func dashboardIncomeLines(
        period: String,
        date: String?,
        offset: Int = 0,
        limit: Int = 50,
        paymentMethod: String? = nil,
        paymentBank: String? = nil,
        cashScope: String? = nil
    ) async throws -> LedgerLinesResponse {
        var path = "/dashboard/income-lines/?period=\(period)&offset=\(offset)&limit=\(limit)"
        if let date { path += "&date=\(date)" }
        if let paymentMethod, !paymentMethod.isEmpty {
            path += "&payment_method=\(paymentMethod.forURLQuery)"
        }
        if let paymentBank, !paymentBank.isEmpty {
            path += "&payment_bank=\(paymentBank.forURLQuery)"
        }
        if let cashScope, !cashScope.isEmpty {
            path += "&cash_scope=\(cashScope.forURLQuery)"
        }
        let data = try await get(path: path)
        if let errResp = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           !errResp.error.isEmpty {
            throw APIError.serverError(errResp.error)
        }
        return try JSONDecoder().decode(LedgerLinesResponse.self, from: data)
    }

    func dashboardSalesLines(
        period: String,
        date: String?,
        profileId: Int?,
        pointId: Int?,
        offset: Int = 0,
        limit: Int = 50
    ) async throws -> LedgerLinesResponse {
        var path =
            "/dashboard/sales-lines/?period=\(period)&offset=\(offset)&limit=\(limit)"
        if let date { path += "&date=\(date)" }
        if let profileId { path += "&profile_id=\(profileId)" }
        if let pointId { path += "&point_id=\(pointId)" }
        let data = try await get(path: path)
        if let errResp = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           !errResp.error.isEmpty {
            throw APIError.serverError(errResp.error)
        }
        return try JSONDecoder().decode(LedgerLinesResponse.self, from: data)
    }

    func dashboardExpenseLines(
        period: String,
        date: String?,
        categoryId: Int? = nil,
        personalMoney: Bool? = nil,
        bankStatementUploadId: Int? = nil,
        paymentBank: String? = nil,
        cashOnly: Bool = false,
        offset: Int = 0,
        limit: Int = 50
    ) async throws -> LedgerLinesResponse {
        var path =
            "/dashboard/expense-lines/?period=\(period)&offset=\(offset)&limit=\(limit)"
        if let date { path += "&date=\(date)" }
        if let categoryId { path += "&category_id=\(categoryId)" }
        if let personalMoney { path += "&personal_money=\(personalMoney ? "true" : "false")" }
        if let bankStatementUploadId { path += "&bank_statement_upload_id=\(bankStatementUploadId)" }
        if let paymentBank, !paymentBank.isEmpty { path += "&payment_bank=\(paymentBank.forURLQuery)" }
        if cashOnly { path += "&cash_only=true" }
        let data = try await get(path: path)
        if let errResp = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           !errResp.error.isEmpty {
            throw APIError.serverError(errResp.error)
        }
        return try JSONDecoder().decode(LedgerLinesResponse.self, from: data)
    }

    // MARK: - Chat

    func chatConversations() async throws -> [Conversation] {
        let data = try await get(path: "/chat/conversations/")
        return try JSONDecoder().decode(ConversationsResponse.self, from: data).conversations
    }

    func chatMessages(conversationId: Int, before: Int? = nil, limit: Int = 50) async throws -> MessagesResponse {
        var path = "/chat/conversations/\(conversationId)/messages/?limit=\(limit)"
        if let before { path += "&before=\(before)" }
        let data = try await get(path: path)
        return try JSONDecoder().decode(MessagesResponse.self, from: data)
    }

    func sendChatMessage(conversationId: Int, text: String) async throws -> ChatMessage {
        let body: [String: String] = ["text": text, "message_type": "text"]
        let data = try await postAuth(path: "/chat/conversations/\(conversationId)/messages/send/", body: body)
        return try JSONDecoder().decode(SingleMessageResponse.self, from: data).message
    }

    func createConversation(kind: String, title: String, participantIds: [Int]) async throws -> Conversation {
        let body: [String: Any] = ["kind": kind, "title": title, "participant_ids": participantIds]
        let data = try await postAuthJSON(path: "/chat/conversations/create/", json: body)
        return try JSONDecoder().decode(SingleConversationResponse.self, from: data).conversation
    }

    func markConversationRead(conversationId: Int) async throws {
        _ = try await postAuth(path: "/chat/conversations/\(conversationId)/read/", body: [:])
    }

    func approveMessage(messageId: Int) async throws -> ChatMessage {
        let data = try await postAuth(path: "/chat/messages/\(messageId)/approve/", body: [:])
        return try JSONDecoder().decode(SingleMessageResponse.self, from: data).message
    }

    func rejectMessage(messageId: Int) async throws -> ChatMessage {
        let data = try await postAuth(path: "/chat/messages/\(messageId)/reject/", body: [:])
        return try JSONDecoder().decode(SingleMessageResponse.self, from: data).message
    }

    func pendingApprovals() async throws -> [PendingApprovalItem] {
        let data = try await get(path: "/chat/pending-approvals/")
        return try JSONDecoder().decode(PendingApprovalsResponse.self, from: data).pendingApprovals
    }

    func uploadStatement(fileData: Data, fileName: String) async throws -> ImportStatementResponse {
        let data = try await uploadMultipart(path: "/chat/import-statement/", fileData: fileData, fileName: fileName)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["needs_bank_account"] as? Bool == true {
            let info = ImportNeedsBankAccount(
                iban: json["iban"] as? String ?? "",
                guessedBankCode: json["guessed_bank_code"] as? String ?? "",
                guessedBankId: json["guessed_bank_id"] as? Int,
                errorMessage: json["error"] as? String ?? "Банковский счёт не зарегистрирован"
            )
            throw APIError.needsBankAccount(info)
        }
        return try JSONDecoder().decode(ImportStatementResponse.self, from: data)
    }

    // MARK: - Calendar

    func calendarEvents(month: Int, year: Int) async throws -> CalendarEventsResponse {
        let data = try await get(path: "/calendar/events/?month=\(month)&year=\(year)")
        if let errResp = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           !errResp.error.isEmpty {
            throw APIError.serverError(errResp.error)
        }
        return try JSONDecoder().decode(CalendarEventsResponse.self, from: data)
    }

    func toggleCalendarEvent(eventId: Int) async throws -> CalendarEvent {
        let data = try await postAuth(path: "/calendar/events/\(eventId)/toggle/", body: [:])
        return try JSONDecoder().decode(ToggleEventResponse.self, from: data).event
    }

    // MARK: - Team / employees (настройки → пользователи)

    func teamSnapshot() async throws -> TeamSnapshot {
        let data = try await get(path: "/team/")
        return try JSONDecoder().decode(TeamSnapshot.self, from: data)
    }

    func teamAvailableProfiles(companyId: Int) async throws -> [AvailableProfileRow] {
        let data = try await get(path: "/team/companies/\(companyId)/available-profiles/")
        return try JSONDecoder().decode(TeamAvailableProfilesResponse.self, from: data).profiles
    }

    func teamCreateEmployee(
        companyId: Int,
        roleId: Int,
        email: String,
        firstName: String,
        lastName: String,
        phone: String,
        telegramId: String,
        pointIds: [Int]
    ) async throws {
        let body: [String: Any] = [
            "company_id": companyId,
            "role_id": roleId,
            "email": email,
            "first_name": firstName,
            "last_name": lastName,
            "phone": phone,
            "telegram_id": telegramId,
            "point_ids": pointIds,
        ]
        let data = try await postAuthJSONChecked(path: "/team/employees/new/", json: body)
        _ = try JSONDecoder().decode(TeamOkResponse.self, from: data)
    }

    func teamAttachEmployee(
        companyId: Int,
        roleId: Int,
        profileId: Int,
        pointIds: [Int]
    ) async throws {
        let body: [String: Any] = [
            "company_id": companyId,
            "role_id": roleId,
            "profile_id": profileId,
            "point_ids": pointIds,
        ]
        let data = try await postAuthJSONChecked(path: "/team/employees/attach/", json: body)
        _ = try JSONDecoder().decode(TeamOkResponse.self, from: data)
    }

    // MARK: - Bank Accounts (настройки → банковские счета)

    func bankAccounts() async throws -> [BankAccountItem] {
        let data = try await get(path: "/bank-accounts/")
        return try JSONDecoder().decode(BankAccountsResponse.self, from: data).accounts
    }

    func banksList() async throws -> BanksListResponse {
        let data = try await get(path: "/bank-accounts/banks/")
        return try JSONDecoder().decode(BanksListResponse.self, from: data)
    }

    func addBankAccount(bankId: Int, iban: String, statementFrequency: String) async throws -> BankAccountItem {
        let body: [String: Any] = [
            "bank_id": bankId,
            "iban": iban,
            "statement_frequency": statementFrequency,
        ]
        let data = try await postAuthJSONChecked(path: "/bank-accounts/add/", json: body)
        return try JSONDecoder().decode(BankAccountAddResponse.self, from: data).account
    }

    func deleteBankAccount(id: Int) async throws {
        _ = try await postAuthJSONChecked(path: "/bank-accounts/\(id)/delete/", json: [:])
    }

    // MARK: - Branches (настройки → филиалы)

    func branches() async throws -> [BranchCompany] {
        let data = try await get(path: "/branches/")
        return try JSONDecoder().decode(BranchesResponse.self, from: data).companies
    }

    func addCompany(
        name: String,
        bin: String,
        companyType: String,
        direction: String,
        taxMode: String,
        address: String
    ) async throws -> BranchCompany {
        let body: [String: Any] = [
            "name": name,
            "bin": bin,
            "company_type": companyType,
            "direction": direction,
            "tax_mode": taxMode,
            "address": address,
        ]
        let data = try await postAuthJSONChecked(path: "/branches/companies/add/", json: body)
        return try JSONDecoder().decode(CompanyAddResponse.self, from: data).company
    }

    func editCompany(
        id: Int,
        name: String,
        direction: String,
        taxMode: String,
        bin: String? = nil
    ) async throws -> BranchCompany {
        var body: [String: Any] = [
            "name": name,
            "direction": direction,
            "tax_mode": taxMode,
        ]
        if let bin {
            body["bin"] = bin
        }
        let data = try await postAuthJSONChecked(path: "/branches/companies/\(id)/edit/", json: body)
        struct Resp: Codable { let ok: Bool; let company: BranchCompany }
        return try JSONDecoder().decode(Resp.self, from: data).company
    }

    func editPoint(id: Int, address: String) async throws -> BranchPoint {
        let body: [String: Any] = ["address": address]
        let data = try await postAuthJSONChecked(path: "/branches/points/\(id)/edit/", json: body)
        return try JSONDecoder().decode(PointEditResponse.self, from: data).point
    }

    func addPoint(companyId: Int, address: String) async throws -> BranchPoint {
        let body: [String: Any] = [
            "company_id": companyId,
            "address": address,
        ]
        let data = try await postAuthJSONChecked(path: "/branches/points/add/", json: body)
        return try JSONDecoder().decode(PointAddResponse.self, from: data).point
    }

    func deletePoint(id: Int) async throws {
        _ = try await postAuthJSONChecked(path: "/branches/points/\(id)/delete/", json: [:])
    }

    // MARK: - Support / maintenance

    func deleteAllTransactionsConfirmed() async throws -> DeleteAllTransactionsResponse {
        let data = try await postAuthJSONChecked(
            path: "/support/delete-all-transactions/",
            json: ["confirm": true]
        )
        return try JSONDecoder().decode(DeleteAllTransactionsResponse.self, from: data)
    }

    // MARK: - Networking

    private func post(path: String, body: [String: String]) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                throw APIError.unauthorized
            }
            return data
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func postAuth(path: String, body: [String: String], isRetry: Bool = false) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainService.read(key: .accessToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                if !isRetry {
                    _ = try await refreshTokens()
                    return try await postAuth(path: path, body: body, isRetry: true)
                }
                throw APIError.unauthorized
            }
            return data
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func postAuthJSON(path: String, json: [String: Any], isRetry: Bool = false) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainService.read(key: .accessToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                if !isRetry {
                    _ = try await refreshTokens()
                    return try await postAuthJSON(path: path, json: json, isRetry: true)
                }
                throw APIError.unauthorized
            }
            return data
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.networkError(error)
        }
    }

    /// POST with JSON body; treats non-2xx like `get` (decode `ErrorResponse` when possible).
    private func postAuthJSONChecked(path: String, json: [String: Any], isRetry: Bool = false) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainService.read(key: .accessToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 {
                    if !isRetry {
                        _ = try await refreshTokens()
                        return try await postAuthJSONChecked(path: path, json: json, isRetry: true)
                    }
                    throw APIError.unauthorized
                }
                if !(200...299).contains(http.statusCode) {
                    if let errResp = try? JSONDecoder().decode(ErrorResponse.self, from: data),
                       !errResp.error.isEmpty {
                        throw APIError.serverError(errResp.error)
                    }
                    throw APIError.serverError("Ошибка сервера (\(http.statusCode))")
                }
            }
            return data
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func uploadMultipart(path: String, fileData: Data, fileName: String, isRetry: Bool = false) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = KeychainService.read(key: .accessToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/plain\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                if !isRetry {
                    _ = try await refreshTokens()
                    return try await uploadMultipart(path: path, fileData: fileData, fileName: fileName, isRetry: true)
                }
                throw APIError.unauthorized
            }
            return data
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func get(path: String, isRetry: Bool = false) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = KeychainService.read(key: .accessToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 {
                    if !isRetry {
                        _ = try await refreshTokens()
                        return try await get(path: path, isRetry: true)
                    }
                    throw APIError.unauthorized
                }
                if !(200...299).contains(http.statusCode) {
                    if let errResp = try? JSONDecoder().decode(ErrorResponse.self, from: data),
                       !errResp.error.isEmpty {
                        throw APIError.serverError(errResp.error)
                    }
                    throw APIError.serverError("Ошибка сервера (\(http.statusCode))")
                }
            }
            return data
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.networkError(error)
        }
    }
}

private extension String {
    /// Значение query-параметра (кириллица, пробелы).
    var forURLQuery: String {
        addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))) ?? self
    }
}
