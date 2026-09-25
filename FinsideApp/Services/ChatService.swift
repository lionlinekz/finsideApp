import Foundation

@MainActor
@Observable
final class ChatService {
    var conversations: [Conversation] = []
    var pendingApprovals: [PendingApprovalItem] = []
    /// Лента push-уведомлений, прилетевших по WebSocket (новые запросы,
    /// результаты согласований и т.п.). Используется для toast/баннеров в UI.
    var liveNotifications: [ChatNotificationItem] = []
    var isLoading = false
    var error: String?

    /// ID запросов на согласование, по которым прямо сейчас идёт сетевой
    /// вызов. Используется ячейкой `ApprovalWidgetCell`, чтобы показать
    /// спиннер и заблокировать кнопки на время запроса, и для отката
    /// оптимистичного апдейта, если сервер вернёт ошибку.
    var inFlightApprovals: Set<Int> = []
    /// Локальный статус для инвойсов/превью без чат-зеркала.
    var localApprovalStatuses: [Int: ApprovalStatus] = [:]
    /// Загрузка квитанции по message id.
    var inFlightReceiptUploads: Set<Int> = []
    /// Отметка «деньги отправлены» по message id.
    var inFlightMoneySent: Set<Int> = []

    private(set) var totalUnreadCount = 0

    private let ws = WebSocketClient()
    var messagesByConversation: [Int: [ChatMessage]] = [:]

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
        ws.onHistoryCleared = { [weak self] conversationId in
            Task { @MainActor in
                self?.applyHistoryCleared(conversationId: conversationId)
            }
        }
        ws.onNotification = { [weak self] notif in
            Task { @MainActor in
                self?.handleIncomingNotification(notif)
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
            if !error.finside_isCancellationLike {
                self.error = error.localizedDescription
            }
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
            if error.finside_isCancellationLike { return false }
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

    /// Отправить фото с опциональной подписью. UI должен предварительно сжать
    /// изображение до JPEG, чтобы минимизировать трафик.
    @discardableResult
    func sendImages(
        conversationId: Int,
        images: [(data: Data, fileName: String, mimeType: String)],
        caption: String
    ) async -> Bool {
        guard !images.isEmpty else { return false }
        do {
            let msg = try await APIService.shared.sendChatImages(
                conversationId: conversationId,
                images: images,
                caption: caption
            )
            appendMessage(msg, to: conversationId)
            if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
                conversations[idx].lastMessage = msg
            }
            return true
        } catch {
            if !error.finside_isCancellationLike {
                self.error = error.localizedDescription
            }
            return false
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

    /// Очистить историю чата на сервере и локально (как «Очистить чат» в WhatsApp).
    func clearConversationHistory(conversationId: Int) async {
        error = nil
        do {
            try await APIService.shared.clearConversationHistory(conversationId: conversationId)
            applyHistoryCleared(conversationId: conversationId)
        } catch {
            if !error.finside_isCancellationLike {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - Approvals

    func loadPendingApprovals() async {
        do {
            pendingApprovals = try await APIService.shared.pendingApprovals()
        } catch {}
    }

    /// Сообщение согласования для модалки действий: сначала кэш, затем подгрузка чата.
    func approvalMessage(
        messageId: Int,
        conversationId: Int,
        fallback: ApprovalSnapshot? = nil
    ) async -> ChatMessage? {
        if let cached = findMessage(id: messageId, conversationId: conversationId) {
            return applyLocalApprovalStatus(to: cached)
        }
        for (_, msgs) in messagesByConversation {
            if let msg = msgs.first(where: { $0.id == messageId }) {
                return applyLocalApprovalStatus(to: msg)
            }
        }
        if let fallback {
            return applyLocalApprovalStatus(
                to: fallback.asMessage(messageId: messageId, conversationId: conversationId)
            )
        }
        guard conversationId > 0 else { return nil }

        var hasMore = await loadMessages(conversationId: conversationId)
        if let msg = findMessage(id: messageId, conversationId: conversationId) {
            return applyLocalApprovalStatus(to: msg)
        }

        var before = messagesByConversation[conversationId]?.first?.id
        for _ in 0..<8 where hasMore {
            guard let cursor = before else { break }
            hasMore = await loadMessages(conversationId: conversationId, before: cursor)
            if let msg = findMessage(id: messageId, conversationId: conversationId) {
                return applyLocalApprovalStatus(to: msg)
            }
            before = messagesByConversation[conversationId]?.first?.id
            if before == cursor { break }
        }
        return nil
    }

    private func applyLocalApprovalStatus(to message: ChatMessage) -> ChatMessage {
        guard let status = localApprovalStatuses[message.id] else { return message }
        var copy = message
        copy.approvalStatus = status
        return copy
    }

    private func findMessage(id messageId: Int, conversationId: Int) -> ChatMessage? {
        if let msg = messagesByConversation[conversationId]?.first(where: { $0.id == messageId }) {
            return msg
        }
        if let conv = conversations.first(where: { $0.id == conversationId }),
           let last = conv.lastMessage,
           last.id == messageId {
            return last
        }
        return nil
    }

    func approve(messageId: Int) async {
        await resolveApproval(messageId: messageId, newStatus: .approved)
    }

    func reject(messageId: Int) async {
        await resolveApproval(messageId: messageId, newStatus: .rejected)
    }

    func resolveApproval(message: ChatMessage, newStatus: ApprovalStatus) async {
        if message.isInvoiceOnly, let invoiceId = message.linkedInvoiceId {
            await resolveInvoiceApproval(
                messageId: message.id,
                invoiceId: invoiceId,
                tenantSchema: message.payload.tenantSchema,
                newStatus: newStatus
            )
            return
        }
        switch newStatus {
        case .approved:
            await approve(messageId: message.id)
        case .rejected:
            await reject(messageId: message.id)
        case .pending:
            break
        }
    }

    private func resolveInvoiceApproval(
        messageId: Int,
        invoiceId: Int,
        tenantSchema: String?,
        newStatus: ApprovalStatus
    ) async {
        let previousStatus = localApprovalStatuses[messageId] ?? .pending
        guard previousStatus != newStatus else { return }

        inFlightApprovals.insert(messageId)
        localApprovalStatuses[messageId] = newStatus
        pendingApprovals.removeAll { $0.id == messageId }

        do {
            switch newStatus {
            case .approved:
                try await APIService.shared.approveInvoice(
                    invoiceId: invoiceId,
                    tenantSchema: tenantSchema
                )
            case .rejected:
                try await APIService.shared.rejectInvoice(
                    invoiceId: invoiceId,
                    tenantSchema: tenantSchema
                )
            case .pending:
                inFlightApprovals.remove(messageId)
                return
            }
            inFlightApprovals.remove(messageId)
            NotificationCenter.default.post(name: .finsideLedgerDidChange, object: nil)
        } catch {
            localApprovalStatuses[messageId] = previousStatus
            inFlightApprovals.remove(messageId)
            if !error.finside_isCancellationLike {
                self.error = error.localizedDescription
            }
        }
    }

    /// Управляющий отмечает, что деньги отправлены инициатору.
    func markMoneySent(messageId: Int) async -> Bool {
        inFlightMoneySent.insert(messageId)
        defer { inFlightMoneySent.remove(messageId) }
        do {
            let updated = try await APIService.shared.markMoneySent(messageId: messageId)
            replaceMessage(updated)
            return true
        } catch {
            if !error.finside_isCancellationLike {
                self.error = error.localizedDescription
            }
            return false
        }
    }

    /// Прикрепить Kaspi PDF к согласованному запросу инициатора.
    func attachReceipt(messageId: Int, fileData: Data, fileName: String) async -> Bool {
        inFlightReceiptUploads.insert(messageId)
        defer { inFlightReceiptUploads.remove(messageId) }
        do {
            let updated = try await APIService.shared.attachApprovalReceipt(
                messageId: messageId,
                fileData: fileData,
                fileName: fileName
            )
            replaceMessage(updated)
            NotificationCenter.default.post(name: .finsideLedgerDidChange, object: nil)
            return true
        } catch {
            if !error.finside_isCancellationLike {
                self.error = error.localizedDescription
            }
            return false
        }
    }

    /// Единая реализация согласовать/отклонить с оптимистичным апдейтом:
    /// мы сразу перерисовываем ячейку в нужный статус, ставим маркер
    /// in-flight (на нём ячейка показывает спиннер), а затем подтверждаем
    /// у сервера. Если сервер вернул ошибку — откатываем статус обратно.
    private func resolveApproval(messageId: Int, newStatus: ApprovalStatus) async {
        let previousStatus = findApprovalStatus(for: messageId)
        guard previousStatus != newStatus else { return }

        inFlightApprovals.insert(messageId)
        updateApprovalStatus(messageId: messageId, status: newStatus)
        pendingApprovals.removeAll { $0.id == messageId }

        do {
            let updated: ChatMessage
            switch newStatus {
            case .approved:
                updated = try await APIService.shared.approveMessage(messageId: messageId)
            case .rejected:
                updated = try await APIService.shared.rejectMessage(messageId: messageId)
            case .pending:
                inFlightApprovals.remove(messageId)
                return
            }
            replaceMessage(updated)
            inFlightApprovals.remove(messageId)
        } catch {
            updateApprovalStatus(messageId: messageId, status: previousStatus)
            inFlightApprovals.remove(messageId)
            if !error.finside_isCancellationLike {
                self.error = error.localizedDescription
            }
        }
    }

    private func findApprovalStatus(for messageId: Int) -> ApprovalStatus? {
        for (_, msgs) in messagesByConversation {
            if let m = msgs.first(where: { $0.id == messageId }) {
                return m.approvalStatus
            }
        }
        return nil
    }

    /// Локально обновить статус согласования у сообщения с заданным id.
    /// Полная переустановка массива гарантирует, что наблюдаемый словарь
    /// `messagesByConversation` корректно сигналит SwiftUI о мутации, а
    /// SwiftUI пересобирает ячейку.
    private func updateApprovalStatus(messageId: Int, status: ApprovalStatus?) {
        for (convId, msgs) in messagesByConversation {
            guard let idx = msgs.firstIndex(where: { $0.id == messageId }) else {
                continue
            }
            var copy = msgs
            copy[idx].approvalStatus = status
            messagesByConversation[convId] = copy
            if let lastIdx = conversations.firstIndex(where: { $0.id == convId }),
               conversations[lastIdx].lastMessage?.id == messageId {
                conversations[lastIdx].lastMessage?.approvalStatus = status
            }
            return
        }
    }

    /// Создать запрос на согласование. Сервер:
    /// — найдёт/создаст чат инициатора с управляющими/владельцами;
    /// — опубликует в нём `approval_request` со статусом `pending`;
    /// — разошлёт согласующим push-уведомления.
    /// Возвращает целевой чат, чтобы UI мог в него перейти.
    @discardableResult
    func createApprovalRequest(_ body: CreateApprovalRequestBody) async -> Conversation? {
        do {
            let resp = try await APIService.shared.createApprovalRequest(body)
            // Обновляем локальный кэш чатов и сообщений.
            if let idx = conversations.firstIndex(where: { $0.id == resp.conversation.id }) {
                var existing = conversations[idx]
                existing.lastMessage = resp.message
                conversations[idx] = existing
                let conv = conversations.remove(at: idx)
                conversations.insert(conv, at: 0)
            } else {
                var conv = resp.conversation
                conv.lastMessage = resp.message
                conversations.insert(conv, at: 0)
            }
            appendMessage(resp.message, to: resp.conversation.id)
            return resp.conversation
        } catch {
            if !error.finside_isCancellationLike {
                self.error = error.localizedDescription
            }
            return nil
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

    /// Открыть/создать 1-1 личный чат с пользователем и обновить локальный список.
    func openDirectChat(with userId: Int) async -> Conversation? {
        do {
            let resp = try await APIService.shared.openDirectChat(userId: userId)
            if let idx = conversations.firstIndex(where: { $0.id == resp.conversation.id }) {
                conversations[idx] = resp.conversation
            } else {
                conversations.insert(resp.conversation, at: 0)
            }
            return resp.conversation
        } catch {
            if !error.finside_isCancellationLike {
                self.error = error.localizedDescription
            }
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

    private func handleIncomingNotification(_ notif: ChatNotificationItem) {
        // Простой инвариант: не более 50 уведомлений в ленте.
        liveNotifications.removeAll { $0.stableId == notif.stableId }
        liveNotifications.insert(notif, at: 0)
        if liveNotifications.count > 50 {
            liveNotifications = Array(liveNotifications.prefix(50))
        }
        // Если уведомление — про новый запрос на согласование, подтягиваем
        // pending-список и список чатов, чтобы UI обновился сразу.
        Task {
            await loadPendingApprovals()
            await loadConversations()
        }
    }

    private func applyHistoryCleared(conversationId: Int) {
        messagesByConversation[conversationId] = []
        pendingApprovals.removeAll { $0.conversationId == conversationId }
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].lastMessage = nil
            conversations[idx].unreadCount = 0
        }
        recalcUnread()
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
