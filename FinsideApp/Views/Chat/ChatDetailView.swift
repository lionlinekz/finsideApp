import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct ChatDetailView: View {
    let conversation: Conversation
    @Environment(AppState.self) private var appState
    @Environment(ChatService.self) private var chatService
    @Environment(\.colorScheme) private var colorScheme
    @State private var messageText = ""
    @State private var hasMore = true
    @State private var isLoadingMore = false
    @FocusState private var isInputFocused: Bool
    @State private var showClearChatConfirm = false
    @State private var showApprovalSheet = false
    @State private var categorizationLaunch: CategorizationLaunch?
    @State private var categorizationRefreshToken = 0

    // Attachments
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var pendingImages: [PendingImage] = []
    @State private var isSendingImages = false
    @State private var photoPickerPresented = false

    struct PendingImage: Identifiable {
        let id = UUID()
        let data: Data
        let preview: UIImage
        let fileName: String
        let mimeType: String
    }

    private var canViewFinancialChats: Bool {
        appState.user?.canViewFinancialChats ?? true
    }

    private var messages: [ChatMessage] {
        chatService.messages(for: conversation.id)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    loadOlderControl

                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                        dayDividerBetween(
                            previous: index > 0 ? messages[index - 1] : nil,
                            current: msg
                        )
                        messageCell(for: msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
            .scrollContentBackground(.hidden)
            .background(ChatScenePalette.canvas)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.bottom, 12, for: .scrollContent)
            .simultaneousGesture(
                TapGesture().onEnded { _ in
                    isInputFocused = false
                }
            )
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composerBar
        }
        .navigationTitle(conversation.displayTitle.isEmpty ? "Канал" : conversation.displayTitle)
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showApprovalSheet = true
                    } label: {
                        Label("Запрос на согласование", systemImage: "checkmark.seal")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showClearChatConfirm = true
                    } label: {
                        Label("Очистить чат", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("Меню чата")
            }
        }
        #endif
        .confirmationDialog(
            "Очистить чат?",
            isPresented: $showClearChatConfirm,
            titleVisibility: .visible
        ) {
            Button("Очистить", role: .destructive) {
                Task { await performClearChat() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Все сообщения будут удалены у всех участников канала. Сам канал останется.")
        }
        .sheet(isPresented: $showApprovalSheet) {
            NewApprovalRequestView(preselectedConversationId: conversation.id) { _ in
                // Сообщение появится в текущем чате через WS / локальное обновление.
            }
        }
        .sheet(item: $categorizationLaunch, onDismiss: {
            categorizationRefreshToken += 1
        }) { launch in
            NavigationStack {
                UncategorizedCategorizationView(
                    uploadId: launch.uploadId,
                    iban: launch.iban
                )
            }
        }
        .task {
            hasMore = await chatService.loadMessages(conversationId: conversation.id)
            await chatService.markRead(conversationId: conversation.id)
        }
    }

    // MARK: - Day grouping

    @ViewBuilder
    private func dayDividerBetween(previous: ChatMessage?, current: ChatMessage) -> some View {
        if let prev = previous,
           let d0 = prev.createdAtDate,
           let d1 = current.createdAtDate,
           Calendar.current.isDate(d0, inSameDayAs: d1) {
            EmptyView()
        } else {
            dayDividerLabel(for: current)
        }
    }

    private func dayDividerLabel(for message: ChatMessage) -> some View {
        Text(dayDividerText(for: message))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
    }

    private func dayDividerText(for message: ChatMessage) -> String {
        guard let date = message.createdAtDate else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Сегодня" }
        if cal.isDateInYesterday(date) { return "Вчера" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        if cal.isDate(date, equalTo: Date(), toGranularity: .year) {
            f.dateFormat = "d MMMM"
        } else {
            f.dateStyle = .long
            f.timeStyle = .none
        }
        return f.string(from: date)
    }

    // MARK: - Load older

    @ViewBuilder
    private var loadOlderControl: some View {
        if hasMore {
            Button {
                Task { await loadOlder() }
            } label: {
                HStack(spacing: 6) {
                    if isLoadingMore {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "chevron.compact.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Text("Загрузить ранее")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background {
                    Capsule(style: .continuous)
                        .fill(.thinMaterial)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 0.5)
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoadingMore)
            .padding(.top, 4)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Messages

    @ViewBuilder
    private func messageCell(for msg: ChatMessage) -> some View {
        if !msg.imageAttachments.isEmpty {
            ImageMessageCell(message: msg)
        } else {
            switch msg.messageType {
            case .text:
                TextMessageCell(message: msg)
            case .approvalRequest:
                ApprovalWidgetCell(message: msg)
            case .importSummary:
                if canViewFinancialChats {
                    ImportSummaryCell(
                        message: msg,
                        refreshToken: categorizationRefreshToken
                    ) {
                        categorizationLaunch = CategorizationLaunch(
                            uploadId: msg.payload.uploadId,
                            iban: msg.payload.iban
                        )
                    }
                }
            case .operationLog:
                if canViewFinancialChats {
                    OperationLogCell(message: msg)
                }
            }
        }
    }

    // MARK: - Composer (Messages-style)

    private var composerBar: some View {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSend = (!trimmed.isEmpty || !pendingImages.isEmpty) && !isSendingImages

        return VStack(spacing: 0) {
            if !pendingImages.isEmpty {
                pendingImagesStrip
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            HStack(alignment: .center, spacing: 10) {
                Button {
                    photoPickerPresented = true
                } label: {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background {
                            Circle()
                                .fill(ChatScenePalette.sendIdleFill(colorScheme: colorScheme))
                        }
                }
                .buttonStyle(.plain)
                .disabled(isSendingImages)
                .accessibilityLabel("Прикрепить фото")

                TextField("Сообщение", text: $messageText, axis: .vertical)
                    .textFieldStyle(
                        ComposerTextFieldStyle(fill: ChatScenePalette.composerFieldFill(colorScheme: colorScheme))
                    )
                    .lineLimit(1...6)
                    .focused($isInputFocused)
                    .disabled(isSendingImages)

                Button {
                    sendMessage()
                } label: {
                    if isSendingImages {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                            .frame(width: 32, height: 32)
                            .background {
                                Circle().fill(Color.accentColor)
                            }
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(canSend ? Color.white : Color.secondary)
                            .frame(width: 32, height: 32)
                            .background {
                                Circle()
                                    .fill(
                                        canSend
                                            ? Color.accentColor
                                            : ChatScenePalette.sendIdleFill(colorScheme: colorScheme)
                                    )
                            }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .animation(.easeInOut(duration: 0.18), value: canSend)
            }
            .padding(.horizontal, 16)
            .padding(.top, pendingImages.isEmpty ? (isInputFocused ? 8 : 10) : 8)
            .padding(.bottom, isInputFocused ? 10 : 12)
            .safeAreaPadding(.bottom, isInputFocused ? 2 : 4)
        }
        .frame(maxWidth: .infinity)
        .background {
            composerBarChrome
        }
        .offset(y: isInputFocused ? 6 : 0)
        .animation(.easeOut(duration: 0.22), value: isInputFocused)
        .photosPicker(
            isPresented: $photoPickerPresented,
            selection: $pickedItems,
            maxSelectionCount: 10,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: pickedItems) { _, newItems in
            Task { await loadPickedItems(newItems) }
        }
    }

    private var pendingImagesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingImages) { item in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: item.preview)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button {
                            pendingImages.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(.black.opacity(0.7), in: Circle())
                        }
                        .offset(x: 6, y: -6)
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Фон панели ввода до физического низа экрана (зона индикатора «домой»), чтобы не было «отрезанной» полосы.
    private var composerBarChrome: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(.ultraThinMaterial)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.10 : 0.35),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 1)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !pendingImages.isEmpty {
            let images = pendingImages.map { ($0.data, $0.fileName, $0.mimeType) }
            let caption = text
            messageText = ""
            pendingImages = []
            pickedItems = []
            isSendingImages = true
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            Task {
                _ = await chatService.sendImages(
                    conversationId: conversation.id, images: images, caption: caption
                )
                isSendingImages = false
            }
            return
        }

        guard !text.isEmpty else { return }
        messageText = ""
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        Task {
            await chatService.sendMessage(conversationId: conversation.id, text: text)
        }
    }

    @MainActor
    private func loadPickedItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var loaded: [PendingImage] = []
        for item in items {
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let original = UIImage(data: raw) else { continue }
            // Сжимаем до разумного размера для мобильной отправки.
            let resized = original.finsideResized(maxDimension: 2048)
            guard let jpegData = resized.jpegData(compressionQuality: 0.78) else { continue }
            let previewBase = original.finsideResized(maxDimension: 256)
            let fileName = "photo_\(Int(Date().timeIntervalSince1970 * 1000))_\(loaded.count + 1).jpg"
            loaded.append(
                PendingImage(
                    data: jpegData,
                    preview: previewBase,
                    fileName: fileName,
                    mimeType: "image/jpeg"
                )
            )
        }
        pendingImages.append(contentsOf: loaded)
        pickedItems = []
    }

    private func loadOlder() async {
        guard !isLoadingMore, let firstMsg = messages.first else { return }
        isLoadingMore = true
        hasMore = await chatService.loadMessages(conversationId: conversation.id, before: firstMsg.id)
        isLoadingMore = false
    }

    private func performClearChat() async {
        isInputFocused = false
        await chatService.clearConversationHistory(conversationId: conversation.id)
        hasMore = false
    }
}

// MARK: - Composer field

private struct ComposerTextFieldStyle: TextFieldStyle {
    let fill: Color

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(fill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
    }
}

// MARK: - Image helpers

#if canImport(UIKit)
extension UIImage {
    /// Уменьшает изображение так, чтобы его максимальная сторона была не больше `maxDimension`,
    /// сохраняя пропорции. Используется перед загрузкой фото на сервер, чтобы не отправлять 12-Мп оригиналы.
    func finsideResized(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
#endif

// MARK: - Surface palette

private enum ChatScenePalette {
    static var canvas: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color.secondary.opacity(0.08)
        #endif
    }

    static func composerFieldFill(colorScheme: ColorScheme) -> Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemFill)
        #elseif os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        #endif
    }

    static func sendIdleFill(colorScheme: ColorScheme) -> Color {
        #if os(iOS)
        Color(uiColor: .tertiarySystemFill)
        #elseif os(macOS)
        Color(nsColor: .quaternaryLabelColor).opacity(0.35)
        #else
        Color.secondary.opacity(0.25)
        #endif
    }
}
