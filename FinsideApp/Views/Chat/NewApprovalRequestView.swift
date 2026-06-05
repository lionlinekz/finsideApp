import SwiftUI

/// «Запрос на согласование» — форма, в которой инициатор отправляет запрос
/// управляющему/владельцу. Сервер сам найдёт согласующих, создаст или найдёт
/// существующий чат с ними и опубликует туда `approval_request`-сообщение.
struct NewApprovalRequestView: View {
    @Environment(ChatService.self) private var chatService
    @Environment(\.dismiss) private var dismiss

    /// Опциональный преднабор чата: если пользователь зашёл из конкретного
    /// чата, запрос будет опубликован прямо в него.
    let preselectedConversationId: Int?
    /// Колбэк после успешной отправки. Хост-вью может перейти в чат
    /// согласования.
    let onSent: (Conversation) -> Void

    @State private var subject: String = ""
    @State private var amountText: String = ""
    @State private var details: String = ""
    @State private var isSending = false
    @State private var errorText: String?

    init(
        preselectedConversationId: Int? = nil,
        onSent: @escaping (Conversation) -> Void
    ) {
        self.preselectedConversationId = preselectedConversationId
        self.onSent = onSent
    }

    private var canSend: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Например, «Оплата хостинга»", text: $subject, axis: .vertical)
                        .lineLimit(1...3)
                        .submitLabel(.next)
                } header: {
                    Text("Что согласовать")
                } footer: {
                    Text("Кратко опишите, что именно нужно согласовать.")
                }

                Section {
                    HStack {
                        TextField("0", text: $amountText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text("₸")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Сумма")
                } footer: {
                    Text("Опционально. Появится в карточке согласования у управляющего.")
                }

                Section {
                    TextField("Дополнительные детали", text: $details, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Описание")
                }

                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Label(
                        preselectedConversationId == nil
                            ? "Запрос придёт управляющему и/или владельцу. Если чата с ними ещё нет — он будет создан."
                            : "Запрос будет опубликован в текущий чат.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Запрос на согласование")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Отправить") {
                            Task { await submit() }
                        }
                        .disabled(!canSend)
                    }
                }
            }
        }
    }

    private func submit() async {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSubject.isEmpty else { return }

        let normalizedAmount = amountText
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        let amountToSend = normalizedAmount.isEmpty ? nil : normalizedAmount

        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)

        let body = CreateApprovalRequestBody(
            text: trimmedSubject,
            amount: amountToSend,
            currency: amountToSend == nil ? nil : "KZT",
            detail: trimmedDetails.isEmpty ? nil : trimmedDetails,
            approverUserIds: [],
            conversationId: preselectedConversationId
        )

        errorText = nil
        isSending = true
        let result = await chatService.createApprovalRequest(body)
        isSending = false

        if let conv = result {
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            dismiss()
            onSent(conv)
        } else {
            errorText = chatService.error ?? "Не удалось отправить запрос. Попробуйте позже."
        }
    }
}

#Preview {
    NewApprovalRequestView { _ in }
        .environment(ChatService())
}
