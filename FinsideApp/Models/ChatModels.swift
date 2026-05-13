import Foundation

// MARK: - Conversation

struct Conversation: Codable, Identifiable, Hashable {
    let id: Int
    let kind: String
    let title: String
    let bankAccountIban: String
    let participants: [String]
    var lastMessage: ChatMessage?
    var unreadCount: Int
    let updatedAt: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind, title, participants
        case bankAccountIban = "bank_account_iban"
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
    }

    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var kindLocalized: String {
        switch kind {
        case "internal": return "Внутренний"
        case "external": return "Внешний"
        case "system": return "Система"
        default: return kind
        }
    }

    var kindIcon: String {
        switch kind {
        case "internal": return "person.2"
        case "external": return "building.2"
        case "system": return "doc.text"
        default: return "message"
        }
    }
}

// MARK: - Message

enum MessageType: String, Codable {
    case text
    case approvalRequest = "approval_request"
    case importSummary = "import_summary"
    case operationLog = "operation_log"
}

enum ApprovalStatus: String, Codable {
    case pending
    case approved
    case rejected

    var localized: String {
        switch self {
        case .pending: return "Ожидает"
        case .approved: return "Согласовано"
        case .rejected: return "Отклонено"
        }
    }
}

struct ChatMessage: Codable, Identifiable, Hashable {
    let id: Int
    let conversationId: Int
    let senderId: Int?
    let senderName: String
    let messageType: MessageType
    let text: String
    let payload: MessagePayload
    let isSystem: Bool
    let createdAt: String
    let approvalStatus: ApprovalStatus?

    enum CodingKeys: String, CodingKey {
        case id, text, payload
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case senderName = "sender_name"
        case messageType = "message_type"
        case isSystem = "is_system"
        case createdAt = "created_at"
        case approvalStatus = "approval_status"
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var formattedTime: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt) else {
            return ""
        }
        let display = DateFormatter()
        display.dateFormat = "HH:mm"
        return display.string(from: date)
    }
}

// MARK: - Payload

struct MessagePayload: Codable, Hashable {
    let amount: String?
    let currency: String?
    let description: String?
    let status: String?
    let paymentId: Int?
    let tenantSchema: String?
    let uploadId: Int?
    let bank: String?
    let incomeCount: Int?
    let expenseCount: Int?
    let transferCount: Int?
    let iban: String?
    let event: String?
    let details: String?
    let refId: Int?

    enum CodingKeys: String, CodingKey {
        case amount, currency, description, status, bank, iban, event, details
        case paymentId = "payment_id"
        case tenantSchema = "tenant_schema"
        case uploadId = "upload_id"
        case incomeCount = "income_count"
        case expenseCount = "expense_count"
        case transferCount = "transfer_count"
        case refId = "ref_id"
    }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        amount = try? container?.decodeIfPresent(String.self, forKey: .amount)
        currency = try? container?.decodeIfPresent(String.self, forKey: .currency)
        description = try? container?.decodeIfPresent(String.self, forKey: .description)
        status = try? container?.decodeIfPresent(String.self, forKey: .status)
        paymentId = try? container?.decodeIfPresent(Int.self, forKey: .paymentId)
        tenantSchema = try? container?.decodeIfPresent(String.self, forKey: .tenantSchema)
        uploadId = try? container?.decodeIfPresent(Int.self, forKey: .uploadId)
        bank = try? container?.decodeIfPresent(String.self, forKey: .bank)
        incomeCount = try? container?.decodeIfPresent(Int.self, forKey: .incomeCount)
        expenseCount = try? container?.decodeIfPresent(Int.self, forKey: .expenseCount)
        transferCount = try? container?.decodeIfPresent(Int.self, forKey: .transferCount)
        iban = try? container?.decodeIfPresent(String.self, forKey: .iban)
        event = try? container?.decodeIfPresent(String.self, forKey: .event)
        details = try? container?.decodeIfPresent(String.self, forKey: .details)
        refId = try? container?.decodeIfPresent(Int.self, forKey: .refId)
    }

    init() {
        amount = nil; currency = nil; description = nil; status = nil
        paymentId = nil; tenantSchema = nil; uploadId = nil; bank = nil
        incomeCount = nil; expenseCount = nil; transferCount = nil
        iban = nil; event = nil; details = nil; refId = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(amount, forKey: .amount)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(paymentId, forKey: .paymentId)
        try container.encodeIfPresent(tenantSchema, forKey: .tenantSchema)
        try container.encodeIfPresent(uploadId, forKey: .uploadId)
        try container.encodeIfPresent(bank, forKey: .bank)
        try container.encodeIfPresent(incomeCount, forKey: .incomeCount)
        try container.encodeIfPresent(expenseCount, forKey: .expenseCount)
        try container.encodeIfPresent(transferCount, forKey: .transferCount)
        try container.encodeIfPresent(iban, forKey: .iban)
        try container.encodeIfPresent(event, forKey: .event)
        try container.encodeIfPresent(details, forKey: .details)
        try container.encodeIfPresent(refId, forKey: .refId)
    }
}

// MARK: - API Responses

struct ConversationsResponse: Codable {
    let conversations: [Conversation]
}

struct MessagesResponse: Codable {
    let messages: [ChatMessage]
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case messages
        case hasMore = "has_more"
    }
}

struct SingleMessageResponse: Codable {
    let message: ChatMessage
}

struct SingleConversationResponse: Codable {
    let conversation: Conversation
}

struct PendingApprovalsResponse: Codable {
    let pendingApprovals: [PendingApprovalItem]

    enum CodingKeys: String, CodingKey {
        case pendingApprovals = "pending_approvals"
    }
}

struct PendingApprovalItem: Codable, Identifiable {
    let id: Int
    let conversationId: Int
    let senderName: String
    let text: String
    let payload: MessagePayload
    let createdAt: String
    let conversationTitle: String

    enum CodingKeys: String, CodingKey {
        case id, text, payload
        case conversationId = "conversation_id"
        case senderName = "sender_name"
        case createdAt = "created_at"
        case conversationTitle = "conversation_title"
    }

    var formattedAmount: String {
        guard let amountStr = payload.amount,
              let amount = MoneyAmount(fromString: amountStr) else { return "" }
        return amount.formattedWithCurrency
    }
}

struct ImportStatementResponse: Codable {
    let conversationId: Int
    let messageId: Int
    let summary: ImportSummary
    /// true, если выписка распознана, но новых проводок не создано (как info на вебе).
    let emptyImport: Bool?

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case messageId = "message_id"
        case summary
        case emptyImport = "empty_import"
    }
}

struct ImportSummary: Codable {
    /// nil, если загрузка откатили (нет новых операций) — API отдаёт upload_id: null.
    let uploadId: Int?
    let bank: String
    let incomeCount: Int
    let expenseCount: Int
    let transferCount: Int
    let tenantSchema: String
    let iban: String
    let emptyImport: Bool?

    enum CodingKeys: String, CodingKey {
        case bank, iban
        case uploadId = "upload_id"
        case incomeCount = "income_count"
        case expenseCount = "expense_count"
        case transferCount = "transfer_count"
        case tenantSchema = "tenant_schema"
        case emptyImport = "empty_import"
    }
}

// MARK: - Import: bank account required

/// API returns this when the statement's IBAN has no matching registered bank account.
struct ImportNeedsBankAccount {
    let iban: String
    let guessedBankCode: String
    let guessedBankId: Int?
    let errorMessage: String
}

// MARK: - MoneyAmount convenience

extension MoneyAmount {
    init?(fromString str: String) {
        guard let decimal = Decimal(string: str) else { return nil }
        self.minorUnits = NSDecimalNumber(decimal: decimal * 100).int64Value
    }
}
