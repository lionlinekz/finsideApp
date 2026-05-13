import SwiftUI

struct ChatListView: View {
    @Environment(ChatService.self) private var chatService
    @State private var segment: ChannelsTopSegment = .notifications
    @State private var selectedSubFilter: String?
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 16) {
                    segmentPicker

                    if segment == .chats, !chatService.pendingApprovals.isEmpty {
                        actionRequiredSection
                    }

                    if !subFilterOptions.isEmpty {
                        subFilterBar
                    }

                    if chatService.isLoading && chatService.conversations.isEmpty {
                        loadingPlaceholder
                    } else if filteredConversations.isEmpty {
                        emptyState
                    } else {
                        conversationsList
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .refreshable {
                await chatService.loadConversations()
                await chatService.loadPendingApprovals()
            }
            .navigationTitle("Каналы")
            .toolbar {
                #if os(iOS) || os(visionOS)
                ToolbarItem(placement: .topBarTrailing) {
                    AvatarMenuButton()
                }
                #else
                ToolbarItem(placement: .automatic) {
                    AvatarMenuButton()
                }
                #endif
            }
            .navigationDestination(for: Conversation.self) { conv in
                ChatDetailView(conversation: conv)
            }
            .onChange(of: segment) { _, _ in
                selectedSubFilter = nil
            }
            .onChange(of: chatService.pendingNavigationConversationId) { _, newId in
                flushPendingChatNavigation(newId: newId)
            }
            .onChange(of: chatService.conversations) { _, _ in
                flushPendingChatNavigation(newId: chatService.pendingNavigationConversationId)
            }
        }
    }

    private func flushPendingChatNavigation(newId: Int?) {
        guard let id = newId,
              let conv = chatService.conversations.first(where: { $0.id == id }) else { return }
        navigationPath.append(conv)
        chatService.pendingNavigationConversationId = nil
    }

    // MARK: - Action Required

    private var actionRequiredSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Text("Требуется действие")
                    .font(.headline)
                Spacer()
                Text("\(chatService.pendingApprovals.count)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.2))
                    .clipShape(Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(chatService.pendingApprovals) { item in
                        PendingApprovalCard(item: item) {
                            if let conv = chatService.conversations.first(where: { $0.id == item.conversationId }) {
                                navigationPath.append(conv)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .liquidGlassCard(cornerRadius: 16)
    }

    // MARK: - Сегменты (уведомления / чаты)

    private var segmentPicker: some View {
        Picker("Раздел", selection: $segment) {
            ForEach(ChannelsTopSegment.allCases) { s in
                Text(s.label).tag(s)
            }
        }
        .pickerStyle(.segmented)
    }

    private var subFilterOptions: [SubFilterOption] {
        switch segment {
        case .notifications:
            let kindConversations = chatService.conversations.filter { $0.kind == "system" }
            var seen = Set<String>()
            var options: [SubFilterOption] = []
            for conv in kindConversations {
                let iban = conv.bankAccountIban
                if !iban.isEmpty && seen.insert(iban).inserted {
                    let short = iban.count > 8
                        ? "•••\(iban.suffix(4))"
                        : iban
                    options.append(SubFilterOption(value: iban, label: short, icon: "creditcard.fill"))
                }
            }
            return options.sorted { $0.label < $1.label }
        case .chats:
            var options: [SubFilterOption] = []
            let internalConvs = chatService.conversations.filter { $0.kind == "internal" }
            var seenInt = Set<String>()
            for conv in internalConvs {
                for name in conv.participants where !name.isEmpty && seenInt.insert(name).inserted {
                    options.append(SubFilterOption(value: "int:\(name)", label: name, icon: "person.fill"))
                }
            }
            let externalConvs = chatService.conversations.filter { $0.kind == "external" }
            var seenExt = Set<String>()
            for conv in externalConvs {
                let key = conv.title.isEmpty ? conv.participants.joined(separator: ", ") : conv.title
                if !key.isEmpty && seenExt.insert(key).inserted {
                    options.append(SubFilterOption(value: "ext:\(key)", label: key, icon: "building.2.fill"))
                }
            }
            return options.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        }
    }

    private var subFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SubFilterChip(
                    label: "Все",
                    icon: nil,
                    isSelected: selectedSubFilter == nil
                ) {
                    selectedSubFilter = nil
                }

                ForEach(subFilterOptions) { option in
                    SubFilterChip(
                        label: option.label,
                        icon: option.icon,
                        isSelected: selectedSubFilter == option.value
                    ) {
                        selectedSubFilter = selectedSubFilter == option.value ? nil : option.value
                    }
                }
            }
        }
    }

    private var filteredConversations: [Conversation] {
        let bySegment: [Conversation]
        switch segment {
        case .notifications:
            bySegment = chatService.conversations.filter { $0.kind == "system" }
        case .chats:
            bySegment = chatService.conversations.filter { $0.kind == "internal" || $0.kind == "external" }
        }

        guard let sub = selectedSubFilter else { return bySegment }

        switch segment {
        case .notifications:
            return bySegment.filter { $0.bankAccountIban == sub }
        case .chats:
            if sub.hasPrefix("int:") {
                let name = String(sub.dropFirst(4))
                return bySegment.filter { $0.kind == "internal" && $0.participants.contains(name) }
            }
            if sub.hasPrefix("ext:") {
                let key = String(sub.dropFirst(4))
                return bySegment.filter { conv in
                    guard conv.kind == "external" else { return false }
                    let k = conv.title.isEmpty ? conv.participants.joined(separator: ", ") : conv.title
                    return k == key
                }
            }
            return bySegment
        }
    }

    // MARK: - Conversations List

    private var conversationsList: some View {
        LazyVStack(spacing: 2) {
            ForEach(filteredConversations) { conv in
                Button {
                    navigationPath.append(conv)
                } label: {
                    ConversationRow(conversation: conv)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Empty & Loading

    private var loadingPlaceholder: some View {
        VStack(spacing: 16) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle().fill(Color.secondary.opacity(0.15)).frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)).frame(height: 14)
                        RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.10)).frame(height: 12).frame(maxWidth: 200)
                    }
                    Spacer()
                }
            }
        }
        .redacted(reason: .placeholder)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: segment == .notifications ? "bell.slash" : "message")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(segment == .notifications ? "Нет уведомлений" : "Нет чатов")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(
                segment == .notifications
                    ? "Сюда попадают системные каналы: импорты выписок и записи по счетам"
                    : "Чаты команды и внешних контрагентов появятся при обмене сообщениями и согласованиях"
            )
            .font(.subheadline)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }
}

// MARK: - Верхний сегмент «Каналы»

private enum ChannelsTopSegment: String, CaseIterable, Identifiable {
    case notifications
    case chats
    var id: String { rawValue }
    var label: String {
        switch self {
        case .notifications: return "Уведомления"
        case .chats: return "Чаты"
        }
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(kindColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: conversation.kindIcon)
                    .font(.title3)
                    .foregroundStyle(kindColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(conversation.title.isEmpty ? conversationDisplayName : conversation.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    if let last = conversation.lastMessage {
                        Text(last.formattedTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    if let last = conversation.lastMessage {
                        Text(lastMessagePreview(last))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Нет сообщений")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }

    private var kindColor: Color {
        switch conversation.kind {
        case "internal": return .blue
        case "external": return .purple
        case "system": return .orange
        default: return .secondary
        }
    }

    private var conversationDisplayName: String {
        if conversation.participants.count <= 2 {
            return conversation.participants.joined(separator: ", ")
        }
        return "\(conversation.participants.prefix(2).joined(separator: ", ")) +\(conversation.participants.count - 2)"
    }

    private func lastMessagePreview(_ msg: ChatMessage) -> String {
        switch msg.messageType {
        case .text:
            return msg.isSystem ? "📋 \(msg.text)" : msg.text
        case .approvalRequest:
            let status = msg.approvalStatus ?? .pending
            return "💰 Согласование: \(status.localized)"
        case .importSummary:
            return "📊 Импорт выписки"
        case .operationLog:
            return "📝 \(msg.text)"
        }
    }
}

// MARK: - Sub-Filter Model

struct SubFilterOption: Identifiable {
    let value: String
    let label: String
    let icon: String
    var id: String { value }
}

// MARK: - Sub-Filter Chip

struct SubFilterChip: View {
    let label: String
    let icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? .white : .primary)
            .liquidGlassChip(isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ChatListView()
        .environment(ChatService())
}
