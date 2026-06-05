import SwiftUI

/// «Новый чат» — выбор собеседника из команды или из других пользователей Winside.
/// Аналог экрана iMessage / WhatsApp при создании нового чата.
struct NewChatContactsView: View {
    @Environment(ChatService.self) private var chatService
    @Environment(\.dismiss) private var dismiss

    let onConversationOpened: (Conversation) -> Void

    @State private var team: [ChatContact] = []
    @State private var others: [ChatContact] = []
    @State private var isLoading = false
    @State private var query = ""
    @State private var openingUserId: Int?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Новый чат")
                #if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                    }
                }
                .searchable(text: $query, prompt: "Имя, фамилия или email")
                .task { await load() }
                .onChange(of: query) { _, _ in
                    Task { await load() }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && team.isEmpty && others.isEmpty {
            loadingPlaceholder
        } else if team.isEmpty && others.isEmpty {
            emptyState
        } else {
            List {
                if !team.isEmpty {
                    Section("Моя команда") {
                        ForEach(team) { contact in
                            contactRow(contact)
                        }
                    }
                }
                if !others.isEmpty {
                    Section("Другие пользователи Winside") {
                        ForEach(others) { contact in
                            contactRow(contact)
                        }
                    }
                }
                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func contactRow(_ contact: ChatContact) -> some View {
        Button {
            Task { await openChat(with: contact) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 42, height: 42)
                    Text(contact.initials)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(contact.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if openingUserId == contact.id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(openingUserId != nil)
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 14) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle().fill(.secondary.opacity(0.18)).frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.secondary.opacity(0.18))
                            .frame(height: 12)
                            .frame(maxWidth: 180)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.secondary.opacity(0.12))
                            .frame(height: 10)
                            .frame(maxWidth: 120)
                    }
                    Spacer()
                }
                .padding(.horizontal)
            }
            Spacer()
        }
        .padding(.top, 24)
        .redacted(reason: .placeholder)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "Пока нет контактов" : "Никого не найдено")
                .font(.headline)
                .foregroundStyle(.secondary)
            if query.isEmpty {
                Text("Здесь появятся участники вашей команды и те, с кем вы уже переписывались.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        errorText = nil
        do {
            let resp = try await APIService.shared.chatContacts(query: query)
            team = resp.team
            others = resp.others
        } catch {
            if !error.finside_isCancellationLike {
                errorText = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func openChat(with contact: ChatContact) async {
        openingUserId = contact.id
        defer { openingUserId = nil }

        if let conv = await chatService.openDirectChat(with: contact.id) {
            onConversationOpened(conv)
            dismiss()
        } else if let err = chatService.error {
            errorText = err
        }
    }
}
