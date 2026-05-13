import Foundation

@MainActor
@Observable
final class WebSocketClient {
    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private var reconnectTask: Task<Void, Never>?
    /// Opaque observer token; must be removable from nonisolated `deinit`.
    nonisolated(unsafe) private var tokenObserver: NSObjectProtocol?

    var onMessage: ((ChatMessage) -> Void)?
    var onApprovalUpdate: ((ChatMessage) -> Void)?
    var onTyping: ((Int, String) -> Void)?

    private let wsBaseURL = BackendEnvironment.chatWebSocketURL

    init() {
        tokenObserver = NotificationCenter.default.addObserver(
            forName: .finsideTokensRefreshed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reconnectWithFreshToken()
            }
        }
    }

    deinit {
        if let tokenObserver {
            NotificationCenter.default.removeObserver(tokenObserver)
        }
    }

    /// After JWT refresh, open a new socket with the new access token.
    private func reconnectWithFreshToken() {
        disconnect()
        connect()
    }

    func connect() {
        guard let token = KeychainService.read(key: .accessToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty
        else { return }
        guard var components = URLComponents(string: wsBaseURL) else { return }
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components.url else { return }

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        reconnectAttempts = 0
        receiveLoop()
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    func sendMessage(conversationId: Int, text: String) {
        let payload: [String: Any] = [
            "action": "send_message",
            "conversation_id": conversationId,
            "text": text,
        ]
        send(payload)
    }

    func sendMarkRead(conversationId: Int) {
        send(["action": "mark_read", "conversation_id": conversationId])
    }

    func sendTyping(conversationId: Int) {
        send(["action": "typing", "conversation_id": conversationId])
    }

    // MARK: - Private

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(str)) { _ in }
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.receiveLoop()
                case .failure:
                    self.isConnected = false
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "new_message":
            if let msgData = json["message"],
               let msgJSON = try? JSONSerialization.data(withJSONObject: msgData),
               let msg = try? JSONDecoder().decode(ChatMessage.self, from: msgJSON) {
                onMessage?(msg)
            }
        case "approval_update":
            if let msgData = json["message"],
               let msgJSON = try? JSONSerialization.data(withJSONObject: msgData),
               let msg = try? JSONDecoder().decode(ChatMessage.self, from: msgJSON) {
                onApprovalUpdate?(msg)
            }
        case "typing":
            if let convId = json["conversation_id"] as? Int,
               let userName = json["user_name"] as? String {
                onTyping?(convId, userName)
            }
        default:
            break
        }
    }

    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else { return }
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0)
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            connect()
        }
    }
}
