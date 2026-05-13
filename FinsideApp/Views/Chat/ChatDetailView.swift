import SwiftUI

struct ChatDetailView: View {
    let conversation: Conversation
    @Environment(ChatService.self) private var chatService
    @State private var messageText = ""
    @State private var hasMore = true
    @State private var isLoadingMore = false
    @FocusState private var isInputFocused: Bool

    private var messages: [ChatMessage] {
        chatService.messages(for: conversation.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesList
            inputBar
        }
        .navigationTitle(conversation.title.isEmpty ? "Канал" : conversation.title)
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            hasMore = await chatService.loadMessages(conversationId: conversation.id)
            await chatService.markRead(conversationId: conversation.id)
        }
    }

    // MARK: - Messages List

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if hasMore {
                        Button("Загрузить ещё") {
                            Task { await loadOlder() }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .opacity(isLoadingMore ? 0 : 1)
                        .overlay {
                            if isLoadingMore {
                                ProgressView()
                            }
                        }
                    }

                    ForEach(messages) { msg in
                        messageCell(for: msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Message Cell Router

    @ViewBuilder
    private func messageCell(for msg: ChatMessage) -> some View {
        switch msg.messageType {
        case .text:
            TextMessageCell(message: msg)
        case .approvalRequest:
            ApprovalWidgetCell(message: msg)
        case .importSummary:
            ImportSummaryCell(message: msg)
        case .operationLog:
            OperationLogCell(message: msg)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Сообщение...", text: $messageText, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .focused($isInputFocused)

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.secondary
                        : Color.accentColor)
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .liquidGlassBar()
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""
        Task {
            await chatService.sendMessage(conversationId: conversation.id, text: text)
        }
    }

    private func loadOlder() async {
        guard !isLoadingMore, let firstMsg = messages.first else { return }
        isLoadingMore = true
        hasMore = await chatService.loadMessages(conversationId: conversation.id, before: firstMsg.id)
        isLoadingMore = false
    }
}
