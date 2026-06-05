import Foundation

// MARK: - Conversation

struct Conversation: Codable, Identifiable, Hashable {
    let id: Int
    let kind: String
    let title: String
    let bankAccountIban: String
    let participants: [String]
    let participantIds: [Int]?
    let otherUserId: Int?
    let otherUserName: String?
    var lastMessage: ChatMessage?
    var unreadCount: Int
    let updatedAt: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind, title, participants
        case bankAccountIban = "bank_account_iban"
        case participantIds = "participant_ids"
        case otherUserId = "other_user_id"
        case otherUserName = "other_user_name"
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
        case "direct": return "Личный"
        case "internal": return "Внутренний"
        case "external": return "Внешний"
        case "system": return "Система"
        default: return kind
        }
    }

    var kindIcon: String {
        switch kind {
        case "direct": return "person.crop.circle"
        case "internal": return "person.2"
        case "external": return "building.2"
        case "system": return "doc.text"
        default: return "message"
        }
    }

    /// Заголовок «как в Messages»: для direct — имя собеседника; иначе — title или участники.
    var displayTitle: String {
        if kind == "direct", let name = otherUserName, !name.isEmpty {
            return name
        }
        if !title.isEmpty { return title }
        if participants.count <= 2 {
            return participants.joined(separator: ", ")
        }
        return "\(participants.prefix(2).joined(separator: ", ")) +\(participants.count - 2)"
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

struct ChatAttachment: Codable, Identifiable, Hashable {
    let id: Int
    let kind: String
    let url: String
    let fileName: String?
    let mimeType: String?
    let width: Int?
    let height: Int?
    let byteSize: Int?

    enum CodingKeys: String, CodingKey {
        case id, kind, url
        case fileName = "file_name"
        case mimeType = "mime_type"
        case width, height
        case byteSize = "byte_size"
    }

    var isImage: Bool { kind == "image" }
    var fileURL: URL? { URL(string: url) }

    /// Пропорции для размещения превью (по умолчанию 4:3).
    var aspectRatio: CGFloat {
        guard let w = width, let h = height, w > 0, h > 0 else { return 4.0 / 3.0 }
        return CGFloat(w) / CGFloat(h)
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
    /// `var`, чтобы можно было сделать оптимистичный апдейт после
    /// нажатия «Согласовать/Отклонить» до прихода ответа сервера.
    var approvalStatus: ApprovalStatus?
    /// Управляющий отметил отправку денег (отдельно от статуса согласования).
    var moneySent: Bool?
    let attachments: [ChatAttachment]?

    enum CodingKeys: String, CodingKey {
        case id, text, payload, attachments
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case senderName = "sender_name"
        case messageType = "message_type"
        case isSystem = "is_system"
        case createdAt = "created_at"
        case approvalStatus = "approval_status"
        case moneySent = "money_sent"
    }

    var imageAttachments: [ChatAttachment] {
        (attachments ?? []).filter { $0.isImage }
    }

    /// NOTE: `==` и `hash` намеренно синтезированы по всем полям, а не
    /// только по `id`. SwiftUI использует Equatable при диффе View-tree:
    /// если два `ChatMessage` с одним `id` считаются «равными», ячейка
    /// `ApprovalWidgetCell` не перерисуется после оптимистичного апдейта
    /// `approvalStatus`, и согласование визуально «застревает» в pending
    /// до перезахода в чат.

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

    /// Для разделителей по дням в ленте чата.
    var createdAtDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: createdAt) { return d }
        return ISO8601DateFormatter().date(from: createdAt)
    }
}

// MARK: - Payload

struct MessagePayload: Codable, Hashable {
    let amount: String?
    let currency: String?
    let description: String?
    let status: String?
    let paymentId: Int?
    let paymentStatus: String?
    let refType: String?
    let tenantSchema: String?
    let uploadId: Int?
    let bank: String?
    let incomeCount: Int?
    let expenseCount: Int?
    let transferCount: Int?
    let iban: String?
    /// Сервер ставит `true`, если новых проводок из выписки не добавлено (уже были учтены).
    let emptyImport: Bool?
    let event: String?
    let details: String?
    let refId: Int?

    enum CodingKeys: String, CodingKey {
        case amount, currency, description, status, bank, iban, event, details
        case paymentId = "payment_id"
        case paymentStatus = "payment_status"
        case refType = "ref_type"
        case tenantSchema = "tenant_schema"
        case uploadId = "upload_id"
        case incomeCount = "income_count"
        case expenseCount = "expense_count"
        case transferCount = "transfer_count"
        case emptyImport = "empty_import"
        case refId = "ref_id"
    }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        amount = try? container?.decodeIfPresent(String.self, forKey: .amount)
        currency = try? container?.decodeIfPresent(String.self, forKey: .currency)
        description = try? container?.decodeIfPresent(String.self, forKey: .description)
        status = try? container?.decodeIfPresent(String.self, forKey: .status)
        paymentId = try? container?.decodeIfPresent(Int.self, forKey: .paymentId)
        paymentStatus = try? container?.decodeIfPresent(String.self, forKey: .paymentStatus)
        refType = try? container?.decodeIfPresent(String.self, forKey: .refType)
        tenantSchema = try? container?.decodeIfPresent(String.self, forKey: .tenantSchema)
        uploadId = try? container?.decodeIfPresent(Int.self, forKey: .uploadId)
        bank = try? container?.decodeIfPresent(String.self, forKey: .bank)
        incomeCount = try? container?.decodeIfPresent(Int.self, forKey: .incomeCount)
        expenseCount = try? container?.decodeIfPresent(Int.self, forKey: .expenseCount)
        transferCount = try? container?.decodeIfPresent(Int.self, forKey: .transferCount)
        iban = try? container?.decodeIfPresent(String.self, forKey: .iban)
        emptyImport = try? container?.decodeIfPresent(Bool.self, forKey: .emptyImport)
        event = try? container?.decodeIfPresent(String.self, forKey: .event)
        details = try? container?.decodeIfPresent(String.self, forKey: .details)
        refId = try? container?.decodeIfPresent(Int.self, forKey: .refId)
    }

    init() {
        amount = nil; currency = nil; description = nil; status = nil
        paymentId = nil; paymentStatus = nil; refType = nil
        tenantSchema = nil; uploadId = nil; bank = nil
        incomeCount = nil; expenseCount = nil; transferCount = nil
        iban = nil; emptyImport = nil; event = nil; details = nil; refId = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(amount, forKey: .amount)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(paymentId, forKey: .paymentId)
        try container.encodeIfPresent(paymentStatus, forKey: .paymentStatus)
        try container.encodeIfPresent(refType, forKey: .refType)
        try container.encodeIfPresent(tenantSchema, forKey: .tenantSchema)
        try container.encodeIfPresent(uploadId, forKey: .uploadId)
        try container.encodeIfPresent(bank, forKey: .bank)
        try container.encodeIfPresent(incomeCount, forKey: .incomeCount)
        try container.encodeIfPresent(expenseCount, forKey: .expenseCount)
        try container.encodeIfPresent(transferCount, forKey: .transferCount)
        try container.encodeIfPresent(iban, forKey: .iban)
        try container.encodeIfPresent(emptyImport, forKey: .emptyImport)
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

// MARK: - Contacts

struct ChatContact: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let email: String
    let firstName: String?
    let lastName: String?

    enum CodingKeys: String, CodingKey {
        case id, name, email
        case firstName = "first_name"
        case lastName = "last_name"
    }

    var initials: String {
        let first = (firstName ?? "").trimmingCharacters(in: .whitespaces)
        let last = (lastName ?? "").trimmingCharacters(in: .whitespaces)
        let f = first.first.map { String($0) } ?? ""
        let l = last.first.map { String($0) } ?? ""
        let combined = (f + l).uppercased()
        if !combined.isEmpty { return combined }
        return String((email.first ?? "?")).uppercased()
    }
}

struct ChatContactsResponse: Codable {
    let team: [ChatContact]
    let others: [ChatContact]
}

struct DirectChatOpenResponse: Codable {
    let conversation: Conversation
    let created: Bool
}

// MARK: - Approval Request (создание запроса инициатором)

/// Тело запроса на согласование, которое отправляет инициатор серверу.
struct CreateApprovalRequestBody {
    /// Краткое описание запроса (например, «Оплата аренды»).
    let text: String
    /// Опциональная сумма; если задана — попадёт в `payload.amount`.
    let amount: String?
    /// Валюта (например, «KZT»); если задана — попадёт в `payload.currency`.
    let currency: String?
    /// Опциональное расширенное описание; пишется в `payload.description`.
    let detail: String?
    /// Опциональные ID согласующих. Если пусто — сервер сам подберёт
    /// управляющих/владельцев тенанта.
    let approverUserIds: [Int]
    /// Если задан — запрос будет опубликован в существующий чат.
    let conversationId: Int?
}

struct ApprovalReceiptAttachResponse: Codable {
    let message: ChatMessage
}

struct ApprovalRequestCreateResponse: Codable {
    let conversation: Conversation
    let message: ChatMessage
    let created: Bool
    let approverIds: [Int]?

    enum CodingKeys: String, CodingKey {
        case conversation, message, created
        case approverIds = "approver_ids"
    }
}

// MARK: - Push Notification (через WebSocket / REST)

/// Push-уведомление, прилетающее по WebSocket-каналу или в виде истории.
/// Используется для inline-плашек в UI и обновления бейджа.
struct ChatNotificationItem: Codable, Identifiable, Hashable {
    let id: Int?
    let title: String
    let message: String
    let notificationType: String
    let priority: String
    let iconClass: String?
    let actionUrl: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, message, priority
        case notificationType = "notification_type"
        case iconClass = "icon_class"
        case actionUrl = "action_url"
        case createdAt = "created_at"
    }

    var stableId: String {
        if let id { return "n\(id)" }
        return "\(createdAt)|\(title)"
    }

    static func == (lhs: ChatNotificationItem, rhs: ChatNotificationItem) -> Bool {
        lhs.stableId == rhs.stableId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(stableId)
    }
}

// MARK: - Statement Import

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
