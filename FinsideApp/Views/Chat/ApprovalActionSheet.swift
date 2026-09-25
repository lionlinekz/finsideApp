import SwiftUI

struct ApprovalSheetContext: Identifiable, Hashable {
    let messageId: Int
    let conversationId: Int
    let fallback: ApprovalSnapshot?

    var id: Int { messageId }

    init(messageId: Int, conversationId: Int, fallback: ApprovalSnapshot? = nil) {
        self.messageId = messageId
        self.conversationId = conversationId
        self.fallback = fallback
    }

    init(item: DashboardApprovalItem) {
        self.init(
            messageId: item.id,
            conversationId: item.conversationId,
            fallback: item.approvalSnapshot
        )
    }

    init(item: PendingApprovalItem) {
        self.init(
            messageId: item.id,
            conversationId: item.conversationId,
            fallback: item.approvalSnapshot
        )
    }
}

struct ApprovalActionSheet: View {
    let context: ApprovalSheetContext
    var onOpenChat: ((Int) -> Void)?

    @Environment(ChatService.self) private var chatService
    @Environment(\.dismiss) private var dismiss

    @State private var message: ChatMessage?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Загрузка…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message {
                    ScrollView {
                        VStack(spacing: 20) {
                            ApprovalWidgetCell(message: message)

                            if context.conversationId > 0, onOpenChat != nil {
                                Button {
                                    dismiss()
                                    onOpenChat?(context.conversationId)
                                } label: {
                                    Label("Открыть в чате", systemImage: "bubble.left.and.bubble.right")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                            }
                        }
                        .padding()
                    }
                } else {
                    ContentUnavailableView(
                        "Не удалось загрузить",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError ?? "Запрос на согласование не найден")
                    )
                }
            }
            .navigationTitle("Согласование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .task(id: context.id) {
                await loadMessage()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func loadMessage() async {
        isLoading = true
        loadError = nil
        message = await chatService.approvalMessage(
            messageId: context.messageId,
            conversationId: context.conversationId,
            fallback: context.fallback
        )
        if message == nil {
            loadError = "Запрос на согласование не найден"
        }
        isLoading = false
    }
}
