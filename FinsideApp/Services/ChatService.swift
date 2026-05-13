import Foundation

@MainActor
@Observable
final class ChatService {
    var conversations: [Conversation] = []
    var pendingApprovals: [PendingApprovalItem] = []
    var isLoading = false
    var error: String?

    private(set) var totalUnreadCount = 0

    private let ws = WebSocketClient()
    private var messagesByConversation: [Int: [ChatMessage]] = [:]

    init() {
        ws.onMessage = { [weak self] msg in
            Task { @MainActor in
                self?.handleIncomingMessage(msg)
            }
        }
        ws.onApprovalUpdate = { [weak self] msg in
            Task { @MainActor in
                self?.handleApprovalUpdate(msg)
            }
        }
    }

    // MARK: - Lifecycle

    func start() {
        ws.connect()
        Task {
            await loadConversations()
            await loadPendingApprovals()
        }
    }

    func stop() {
        ws.disconnect()
    }

    // MARK: - Conversations

    func loadConversations() async {
        isLoading = true
        error = nil
        do {
            conversations = try await APIService.shared.chatConversations()
            recalcUnread()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Messages

    func messages(for conversationId: Int) -> [ChatMessage] {
        messagesByConversation[conversationId] ?? []
    }

    func loadMessages(conversationId: Int, before: Int? = nil) async -> Bool {
        do {
            let response = try await APIService.shared.chatMessages(
                conversationId: conversationId, before: before
            )
            if before == nil {
                messagesByConversation[conversationId] = response.messages
            } else {
                var existing = messagesByConversation[conversationId] ?? []
                existing.insert(contentsOf: response.messages, at: 0)
                messagesByConversation[conversationId] = existing
            }
            return response.hasMore
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func sendMessage(conversationId: Int, text: String) async {
        do {
            let msg = try await APIService.shared.sendChatMessage(
                conversationId: conversationId, text: text
            )
            appendMessage(msg, to: conversationId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func markRead(conversationId: Int) async {
        do {
            try await APIService.shared.markConversationRead(conversationId: conversationId)
            ws.sendMarkRead(conversationId: conversationId)
            if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
                conversations[idx].unreadCount = 0
            }
            recalcUnread()
        } catch {}
    }

    // MARK: - Approvals

    func loadPendingApprovals() async {
        do {
            pendingApprovals = try await APIService.shared.pendingApprovals()
        } catch {}
    }

    func approve(messageId: Int) async {
        do {
            let updated = try await APIService.shared.approveMessage(messageId: messageId)
            replaceMessage(updated)
            pendingApprovals.removeAll { $0.id == messageId }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reject(messageId: Int) async {
        do {
            let updated = try await APIService.shared.rejectMessage(messageId: messageId)
            replaceMessage(updated)
            pendingApprovals.removeAll { $0.id == messageId }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Create Conversation

    func createConversation(kind: String, title: String, participantIds: [Int]) async -> Conversation? {
        do {
            let conv = try await APIService.shared.createConversation(
                kind: kind, title: title, participantIds: participantIds
            )
            conversations.insert(conv, at: 0)
            return conv
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    // MARK: - Statement Upload

    /// Throws `APIError.needsBankAccount` when the IBAN is not registered — caller should handle it.
    func uploadStatement(data: Data, fileName: String) async throws -> ImportStatementResponse {
        let resp = try await APIService.shared.uploadStatement(fileData: data, fileName: fileName)
        await loadConversations()
        await loadPendingApprovals()
        return resp
    }

    // MARK: - Deep Link

    var pendingNavigationConversationId: Int?

    /// Переключить на вкладку «Каналы» без открытия конкретного диалога (например, если канал по IBAN ещё не создан).
    var pendingOpenChatsTab = false

    func navigateToConversation(id: Int) {
        pendingNavigationConversationId = id
    }

    /// Открыть системный канал по IBAN (импорт выписок) или просто вкладку каналов.
    func openBankStatementChannelOrChatsTab(preferredIban: String) async {
        let key = Self.normalizeIban(preferredIban)
        if conversations.isEmpty || !conversations.contains(where: {
            $0.kind == "system" && Self.normalizeIban($0.bankAccountIban) == key && !key.isEmpty
        }) {
            await loadConversations()
        }
        if let conv = conversations.first(where: {
            $0.kind == "system" && Self.normalizeIban($0.bankAccountIban) == key && !key.isEmpty
        }) {
            navigateToConversation(id: conv.id)
        } else {
            pendingOpenChatsTab = true
        }
    }

    private static func normalizeIban(_ raw: String) -> String {
        raw.replacingOccurrences(of: " ", with: "").uppercased()
    }

    // MARK: - Private

    private func handleIncomingMessage(_ msg: ChatMessage) {
        appendMessage(msg, to: msg.conversationId)
        if let idx = conversations.firstIndex(where: { $0.id == msg.conversationId }) {
            conversations[idx].lastMessage = msg
            conversations[idx].unreadCount += 1
            let conv = conversations.remove(at: idx)
            conversations.insert(conv, at: 0)
        } else {
            Task { await loadConversations() }
        }
        recalcUnread()
    }

    private func handleApprovalUpdate(_ msg: ChatMessage) {
        replaceMessage(msg)
        pendingApprovals.removeAll { $0.id == msg.id }
    }

    private func appendMessage(_ msg: ChatMessage, to conversationId: Int) {
        var msgs = messagesByConversation[conversationId] ?? []
        if !msgs.contains(where: { $0.id == msg.id }) {
            msgs.append(msg)
        }
        messagesByConversation[conversationId] = msgs
    }

    private func replaceMessage(_ msg: ChatMessage) {
        guard var msgs = messagesByConversation[msg.conversationId],
              let idx = msgs.firstIndex(where: { $0.id == msg.id }) else { return }
        msgs[idx] = msg
        messagesByConversation[msg.conversationId] = msgs
    }

    private func recalcUnread() {
        totalUnreadCount = conversations.reduce(0) { $0 + $1.unreadCount }
    }
}
